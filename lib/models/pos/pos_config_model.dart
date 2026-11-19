import 'package:cloud_firestore/cloud_firestore.dart';

/// Desteklenen Sanal POS sağlayıcıları.
class PosProviders {
  static const String iyzico = 'iyzico';
  static const String paytr = 'paytr';
  static const String param = 'param';
  static const String sipay = 'sipay';
  static const String bank3d = 'bank_3d';

  static const List<String> all = [iyzico, paytr, param, sipay, bank3d];

  static String labelOf(String provider) {
    switch (provider) {
      case iyzico:
        return 'iyzico Sanal POS';
      case paytr:
        return 'PayTR Sanal POS';
      case param:
        return 'ParamPOS';
      case sipay:
        return 'Sipay Sanal POS';
      case bank3d:
        return 'Banka Ortak 3D POS';
      default:
        return provider.toUpperCase();
    }
  }
}

/// Modül bazlı POS kanal çalışma modları.
class PosChannelModes {
  /// Kurumun tanımladığı Ana / Genel POS hesabını kullanır.
  static const String inheritSchool = 'inherit_school';

  /// İlgili modül (örn. Kantin veya Okul Mağazası) için tamamen ayrı POS hesabı kullanır.
  static const String custom = 'custom';

  /// Merkezi sistem / test POS altyapısını kullanır.
  static const String platformDefault = 'platform_default';

  static String labelOf(String mode, {required String moduleLabel}) {
    switch (mode) {
      case custom:
        return '$moduleLabel İçin Ayrı Özel POS Kullan';
      case inheritSchool:
        return 'Kurum Ana POS Hesabını Kullan';
      case platformDefault:
      default:
        return 'Merkezi / Varsayılan POS Altyapısını Kullan';
    }
  }
}

/// Tek bir Sanal POS kimlik ve çalışma profili.
class PosCredentialProfile {
  final bool enabled;
  final String provider; // 'iyzico' | 'paytr' | ...
  final String environment; // 'sandbox' | 'production'
  final String merchantTitle;
  final String apiKey;
  final String secretKey;
  final String baseUrl;
  final String subMerchantKey;
  final bool allowInstallments;
  final List<int> enabledInstallments;
  final String terminalNote;

  const PosCredentialProfile({
    this.enabled = false,
    this.provider = PosProviders.iyzico,
    this.environment = 'sandbox',
    this.merchantTitle = '',
    this.apiKey = '',
    this.secretKey = '',
    this.baseUrl = '',
    this.subMerchantKey = '',
    this.allowInstallments = true,
    this.enabledInstallments = const [1, 2, 3, 6, 9],
    this.terminalNote = '',
  });

  static const List<int> allInstallmentOptions = [1, 2, 3, 4, 6, 9, 12];

  bool get hasCredentials =>
      apiKey.trim().isNotEmpty && secretKey.trim().isNotEmpty;

  bool get isReady => enabled && hasCredentials;

  String get effectiveBaseUrl {
    final trimmed = baseUrl.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return environment == 'production'
        ? 'https://api.iyzipay.com'
        : 'https://sandbox-api.iyzipay.com';
  }

  String get maskedApiKey {
    final k = apiKey.trim();
    if (k.isEmpty) return 'Tanımlı değil';
    if (k.length <= 8) return '${k.substring(0, 2)}••••';
    return '${k.substring(0, 6)}••••${k.substring(k.length - 4)}';
  }

  factory PosCredentialProfile.fromMap(
    Map<String, dynamic>? map, {
    bool defaultAllowInstallments = true,
    List<int> defaultInstallments = const [1, 2, 3, 6, 9],
  }) {
    if (map == null) {
      return PosCredentialProfile(
        allowInstallments: defaultAllowInstallments,
        enabledInstallments: defaultInstallments,
      );
    }
    final rawInst = map['enabledInstallments'];
    final parsedInst = <int>[];
    if (rawInst is Iterable) {
      for (final x in rawInst) {
        final v = x is num ? x.toInt() : int.tryParse(x.toString());
        if (v != null && v >= 1 && v <= 12 && !parsedInst.contains(v)) {
          parsedInst.add(v);
        }
      }
    }
    if (!parsedInst.contains(1)) parsedInst.insert(0, 1);
    parsedInst.sort();

    return PosCredentialProfile(
      enabled: map['enabled'] as bool? ?? false,
      provider: (map['provider'] ?? PosProviders.iyzico).toString().trim(),
      environment: (map['environment'] ?? 'sandbox').toString().trim(),
      merchantTitle: (map['merchantTitle'] ?? '').toString().trim(),
      apiKey: (map['apiKey'] ?? '').toString().trim(),
      secretKey: (map['secretKey'] ?? '').toString().trim(),
      baseUrl: (map['baseUrl'] ?? '').toString().trim(),
      subMerchantKey: (map['subMerchantKey'] ?? '').toString().trim(),
      allowInstallments:
          map['allowInstallments'] as bool? ?? defaultAllowInstallments,
      enabledInstallments: parsedInst.isEmpty
          ? defaultInstallments
          : parsedInst,
      terminalNote: (map['terminalNote'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    final normalizedInst = <int>{
      1,
      if (allowInstallments) ...enabledInstallments,
    }.toList()..sort();
    return {
      'enabled': enabled,
      'provider': provider,
      'environment': environment,
      'merchantTitle': merchantTitle.trim(),
      'apiKey': apiKey.trim(),
      'secretKey': secretKey.trim(),
      'baseUrl': baseUrl.trim(),
      'subMerchantKey': subMerchantKey.trim(),
      'allowInstallments': allowInstallments,
      'enabledInstallments': allowInstallments ? normalizedInst : const [1],
      'terminalNote': terminalNote.trim(),
    };
  }

  PosCredentialProfile copyWith({
    bool? enabled,
    String? provider,
    String? environment,
    String? merchantTitle,
    String? apiKey,
    String? secretKey,
    String? baseUrl,
    String? subMerchantKey,
    bool? allowInstallments,
    List<int>? enabledInstallments,
    String? terminalNote,
  }) {
    return PosCredentialProfile(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      environment: environment ?? this.environment,
      merchantTitle: merchantTitle ?? this.merchantTitle,
      apiKey: apiKey ?? this.apiKey,
      secretKey: secretKey ?? this.secretKey,
      baseUrl: baseUrl ?? this.baseUrl,
      subMerchantKey: subMerchantKey ?? this.subMerchantKey,
      allowInstallments: allowInstallments ?? this.allowInstallments,
      enabledInstallments: enabledInstallments ?? this.enabledInstallments,
      terminalNote: terminalNote ?? this.terminalNote,
    );
  }
}

/// Modül bazlı (Mağaza / Kantin / Muhasebe) POS yönlendirme ayarı.
class PosChannelConfig {
  final String mode; // 'inherit_school' | 'custom' | 'platform_default'
  final PosCredentialProfile customProfile;

  const PosChannelConfig({
    this.mode = PosChannelModes.inheritSchool,
    this.customProfile = const PosCredentialProfile(),
  });

  factory PosChannelConfig.fromMap(
    Map<String, dynamic>? map, {
    String defaultMode = PosChannelModes.inheritSchool,
    bool defaultAllowInstallments = true,
    List<int> defaultInstallments = const [1, 2, 3, 6, 9],
  }) {
    if (map == null) {
      return PosChannelConfig(
        mode: defaultMode,
        customProfile: PosCredentialProfile(
          allowInstallments: defaultAllowInstallments,
          enabledInstallments: defaultInstallments,
        ),
      );
    }
    return PosChannelConfig(
      mode: (map['mode'] ?? defaultMode).toString().trim(),
      customProfile: PosCredentialProfile.fromMap(
        map['customProfile'] is Map
            ? Map<String, dynamic>.from(map['customProfile'] as Map)
            : null,
        defaultAllowInstallments: defaultAllowInstallments,
        defaultInstallments: defaultInstallments,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'mode': mode,
    'customProfile': customProfile.toMap(),
  };

  PosChannelConfig copyWith({
    String? mode,
    PosCredentialProfile? customProfile,
  }) {
    return PosChannelConfig(
      mode: mode ?? this.mode,
      customProfile: customProfile ?? this.customProfile,
    );
  }
}

/// Bir kuruma (`pos_configs/{INSTITUTION_ID}` veya `pos_configs/SUPER_ADMIN`) ait
/// tüm Sanal POS profillerini (Kurum Ana POS, Mağaza POS, Kantin POS, Muhasebe POS) tutar.
class InstitutionPosConfig {
  final String institutionId;
  final PosCredentialProfile defaultPos;
  final PosChannelConfig storePos;
  final PosChannelConfig canteenPos;
  final PosChannelConfig accountingPos;
  final DateTime updatedAt;

  const InstitutionPosConfig({
    required this.institutionId,
    this.defaultPos = const PosCredentialProfile(),
    this.storePos = const PosChannelConfig(mode: PosChannelModes.inheritSchool),
    this.canteenPos = const PosChannelConfig(
      mode: PosChannelModes.inheritSchool,
      customProfile: PosCredentialProfile(
        allowInstallments: false,
        enabledInstallments: [1],
      ),
    ),
    this.accountingPos = const PosChannelConfig(
      mode: PosChannelModes.inheritSchool,
    ),
    required this.updatedAt,
  });

  factory InstitutionPosConfig.defaults(String institutionId) {
    return InstitutionPosConfig(
      institutionId: institutionId.trim().toUpperCase(),
      updatedAt: DateTime.now(),
    );
  }

  factory InstitutionPosConfig.fromMap(
    String institutionId,
    Map<String, dynamic>? map,
  ) {
    final upper = institutionId.trim().toUpperCase();
    if (map == null) return InstitutionPosConfig.defaults(upper);
    DateTime parsedDate = DateTime.now();
    final rawUpdated = map['updatedAt'];
    if (rawUpdated is Timestamp) {
      parsedDate = rawUpdated.toDate();
    } else if (rawUpdated is DateTime) {
      parsedDate = rawUpdated;
    }

    return InstitutionPosConfig(
      institutionId: upper,
      defaultPos: PosCredentialProfile.fromMap(
        map['defaultPos'] is Map
            ? Map<String, dynamic>.from(map['defaultPos'] as Map)
            : null,
      ),
      storePos: PosChannelConfig.fromMap(
        map['storePos'] is Map
            ? Map<String, dynamic>.from(map['storePos'] as Map)
            : null,
        defaultMode: PosChannelModes.inheritSchool,
        defaultAllowInstallments: true,
        defaultInstallments: const [1, 2, 3, 6, 9],
      ),
      canteenPos: PosChannelConfig.fromMap(
        map['canteenPos'] is Map
            ? Map<String, dynamic>.from(map['canteenPos'] as Map)
            : null,
        defaultMode: PosChannelModes.inheritSchool,
        defaultAllowInstallments: false,
        defaultInstallments: const [1],
      ),
      accountingPos: PosChannelConfig.fromMap(
        map['accountingPos'] is Map
            ? Map<String, dynamic>.from(map['accountingPos'] as Map)
            : null,
        defaultMode: PosChannelModes.inheritSchool,
        defaultAllowInstallments: true,
        defaultInstallments: const [1, 2, 3, 6, 9, 12],
      ),
      updatedAt: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    final upper = institutionId.trim().toUpperCase();
    return {
      'institutionId': upper,
      'defaultPos': defaultPos.toMap(),
      'storePos': storePos.toMap(),
      'canteenPos': canteenPos.toMap(),
      'accountingPos': accountingPos.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  PosChannelConfig channelOf(String channel) {
    switch (channel) {
      case 'canteen':
        return canteenPos;
      case 'accounting':
        return accountingPos;
      case 'store':
      default:
        return storePos;
    }
  }

  /// İlgili modül (`'store'` | `'canteen'` | `'accounting'`) kurumun kendi
  /// özel veya ana POS hesabını mı kullanıyor?
  bool usesInstitutionCustomPos(String channel) {
    final ch = channelOf(channel);
    if (ch.mode == PosChannelModes.custom) {
      return ch.customProfile.isReady;
    }
    if (ch.mode == PosChannelModes.inheritSchool) {
      return defaultPos.isReady;
    }
    return false;
  }

  /// İlgili modül için aktif olan `PosCredentialProfile` nesnesini döndürür
  /// (`null` ise merkezi/platform varsayılan POS devrededir).
  PosCredentialProfile? resolveActiveProfile(String channel) {
    final ch = channelOf(channel);
    if (ch.mode == PosChannelModes.custom) {
      return ch.customProfile.isReady ? ch.customProfile : null;
    }
    if (ch.mode == PosChannelModes.inheritSchool) {
      return defaultPos.isReady ? defaultPos : null;
    }
    return null;
  }

  /// Kullanıcı arayüzünde gösterilecek kısa POS özet etiketi (gizli anahtar içermez).
  String summaryLabelFor(String channel) {
    final ch = channelOf(channel);
    if (ch.mode == PosChannelModes.custom) {
      if (ch.customProfile.isReady) {
        final title = ch.customProfile.merchantTitle.isNotEmpty
            ? ch.customProfile.merchantTitle
            : PosProviders.labelOf(ch.customProfile.provider);
        final env = ch.customProfile.environment == 'production'
            ? 'Canlı'
            : 'Test';
        return 'Özel POS: $title ($env)';
      }
      return 'Özel POS Seçili (Anahtar Eksik)';
    }
    if (ch.mode == PosChannelModes.inheritSchool) {
      if (defaultPos.isReady) {
        final title = defaultPos.merchantTitle.isNotEmpty
            ? defaultPos.merchantTitle
            : PosProviders.labelOf(defaultPos.provider);
        final env = defaultPos.environment == 'production' ? 'Canlı' : 'Test';
        return 'Kurum POS: $title ($env)';
      }
      return 'Varsayılan Platform POS (Kurum POS Tanımsız)';
    }
    return 'Merkezi Platform POS';
  }

  InstitutionPosConfig copyWith({
    PosCredentialProfile? defaultPos,
    PosChannelConfig? storePos,
    PosChannelConfig? canteenPos,
    PosChannelConfig? accountingPos,
    DateTime? updatedAt,
  }) {
    return InstitutionPosConfig(
      institutionId: institutionId,
      defaultPos: defaultPos ?? this.defaultPos,
      storePos: storePos ?? this.storePos,
      canteenPos: canteenPos ?? this.canteenPos,
      accountingPos: accountingPos ?? this.accountingPos,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

