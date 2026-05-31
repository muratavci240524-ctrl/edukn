import 'package:cloud_firestore/cloud_firestore.dart';

enum SmsProvider { netgsm, iletisim360, mutlucell, custom }

class SmsSettings {
  final SmsProvider provider;
  final String apiKey;
  final String apiSecret;
  final String originator;
  final String? customApiUrl;
  final bool isActive;
  final DateTime? lastTestedAt;
  final String? lastTestResult;
  final DateTime? updatedAt;
  final String? updatedBy;

  const SmsSettings({
    required this.provider,
    required this.apiKey,
    required this.apiSecret,
    required this.originator,
    this.customApiUrl,
    this.isActive = false,
    this.lastTestedAt,
    this.lastTestResult,
    this.updatedAt,
    this.updatedBy,
  });

  String get providerName {
    switch (provider) {
      case SmsProvider.netgsm:
        return 'Netgsm';
      case SmsProvider.iletisim360:
        return 'İletişim360';
      case SmsProvider.mutlucell:
        return 'Mutlucell';
      case SmsProvider.custom:
        return 'Özel API';
    }
  }

  String get providerApiUrl {
    switch (provider) {
      case SmsProvider.netgsm:
        return 'https://api.netgsm.com.tr/sms/send/get';
      case SmsProvider.iletisim360:
        return 'https://api.iletisim360.com/v1/sms/send';
      case SmsProvider.mutlucell:
        return 'https://api.mutlucell.com/api-utf8/sms-add';
      case SmsProvider.custom:
        return customApiUrl ?? '';
    }
  }

  static SmsProvider _providerFromString(String? s) {
    switch (s) {
      case 'netgsm':
        return SmsProvider.netgsm;
      case 'iletisim360':
        return SmsProvider.iletisim360;
      case 'mutlucell':
        return SmsProvider.mutlucell;
      case 'custom':
        return SmsProvider.custom;
      default:
        return SmsProvider.netgsm;
    }
  }

  static String _providerToString(SmsProvider p) {
    switch (p) {
      case SmsProvider.netgsm:
        return 'netgsm';
      case SmsProvider.iletisim360:
        return 'iletisim360';
      case SmsProvider.mutlucell:
        return 'mutlucell';
      case SmsProvider.custom:
        return 'custom';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'provider': _providerToString(provider),
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'originator': originator,
      'customApiUrl': customApiUrl,
      'isActive': isActive,
      'lastTestedAt': lastTestedAt != null ? Timestamp.fromDate(lastTestedAt!) : null,
      'lastTestResult': lastTestResult,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  factory SmsSettings.fromMap(Map<String, dynamic> map) {
    return SmsSettings(
      provider: _providerFromString(map['provider']),
      apiKey: map['apiKey'] ?? '',
      apiSecret: map['apiSecret'] ?? '',
      originator: map['originator'] ?? '',
      customApiUrl: map['customApiUrl'],
      isActive: map['isActive'] ?? false,
      lastTestedAt: (map['lastTestedAt'] as Timestamp?)?.toDate(),
      lastTestResult: map['lastTestResult'],
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: map['updatedBy'],
    );
  }

  SmsSettings copyWith({
    SmsProvider? provider,
    String? apiKey,
    String? apiSecret,
    String? originator,
    String? customApiUrl,
    bool? isActive,
    DateTime? lastTestedAt,
    String? lastTestResult,
    String? updatedBy,
  }) {
    return SmsSettings(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
      originator: originator ?? this.originator,
      customApiUrl: customApiUrl ?? this.customApiUrl,
      isActive: isActive ?? this.isActive,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      lastTestResult: lastTestResult ?? this.lastTestResult,
      updatedAt: updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
