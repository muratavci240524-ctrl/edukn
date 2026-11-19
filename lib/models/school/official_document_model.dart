import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Evrak hedef kitlesi (rol görünürlüğü)
enum DocAudience {
  admin, // İdari Resmi Evraklar (Müdür / Müdür Yardımcısı)
  teacher, // Öğretmen Resmi Evrakları (Branş / Sınıf Rehber / Kulüp / Nöbet)
  common, // Ortak Hızlı Liste, Çizelge, Veli İzin & Kart Otomasyonları
}

/// Evrakın dayandığı MEB Yönetmelik / Kurum Türü Kapsamı
enum DocRegulationScope {
  ortakMevzuat, // Tüm kademelerde ve kurumlarda geçerli ortak MEB mevzuatı
  ilkogretimOkulOncesi, // MEB Okul Öncesi Eğitim ve İlköğretim Kurumları Yönetmeliği
  ortaogretimLise, // MEB Ortaöğretim Kurumları Yönetmeliği (Lise)
  ozelOgretimKurs, // 5580 S.K. & MEB Özel Öğretim Kurumları / Özel Öğretim Kursları Mevzuatı
}

/// Üst antet görünümü
enum DocHeaderStyle {
  corporateLogo, // Kurumsal Logolu Okul Başlığı
  mebOfficial, // T.C. Valilik / Kaymakamlık / Okul Müdürlüğü Resmi Yazı Anteti
}

/// PDF sayfa ve mizanpaj şablon türü
enum DocLayoutKind {
  officialLetter, // Sayı-Konu, Hitap, Resmi Metin, İmza & Tebellüğ Kutusu
  meetingMinutes, // Kurul / Zümre / ŞÖK / Veli Toplantısı Tutanağı + Kararlar + Katılımcı İmza Sirküsü
  incidentForm, // Bilgi Künyesi Tablosu + Olay/Görüşme/Gözlem Metni + Çoklu İmza Bloğu
  circularSignatureTable, // Üst Duyuru/Analiz/Dağıtım Metni + Numaralı Personel/Öğrenci İmza Çizelgesi
  bulkParentSlip, // Öğrenci Bazlı Toplu Veli İzin / Muvafakatname & Davet Pusulası (1 veya 2'li kesimli)
  dynamicChecklist, // Özelleştirilebilir Sütunlu Kontrol & İmza Çizelgesi (Dikey / Yatay A4)
  badgeGrid, // Kesim Çizgili QR Yaka Kartı / Sınıf Kapı Listesi / Dolap-Sıra Etiketi
}

/// Sihirbazda kullanıcıya sorulacak alan tipleri
enum DocFieldType {
  text,
  multiline,
  date,
  time,
  dropdown,
  multiCheck, // Hazır maddelerden çoklu seçim + özel madde ekleme
  classSelect, // Tek şube seçimi
  multiClassSelect, // Çoklu şube seçimi
  studentSelect, // Tek öğrenci seçimi
  multiStudentSelect, // Çoklu öğrenci seçimi
  staffSelect, // Tek personel/öğretmen seçimi
  multiStaffSelect, // Çoklu personel/öğretmen seçimi
  branchSelect, // Branş/Ders seçimi
  yesNo, // Evet / Hayır seçimi
}

/// Evrak sihirbazındaki tek bir soru alanı
class DocQuestionField {
  final String key;
  final String label;
  final String? hint;
  final DocFieldType type;
  final List<String> options;
  final dynamic defaultValue;
  final bool required;
  final String? helperText;

  const DocQuestionField({
    required this.key,
    required this.label,
    required this.type,
    this.hint,
    this.options = const [],
    this.defaultValue,
    this.required = false,
    this.helperText,
  });
}

/// İmza bloğunda yer alacak tek bir imzacı tanımı
class DocSigner {
  final String name;
  final String title;
  final bool isApproval; // true ise alt ortada "UYGUNDUR / OLUR" bloğu olarak basılır

  const DocSigner({
    required this.name,
    required this.title,
    this.isApproval = false,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'title': title,
        'isApproval': isApproval,
      };

  factory DocSigner.fromMap(Map<String, dynamic> map) => DocSigner(
        name: (map['name'] ?? '').toString(),
        title: (map['title'] ?? '').toString(),
        isApproval: map['isApproval'] == true,
      );
}

/// Ana Başlık (Kategori) tanımı
class OfficialDocCategory {
  final String id;
  final int order;
  final String title;
  final String subtitle;
  final DocAudience audience;
  final IconData icon;
  final Color color;
  final List<DocRegulationScope> scopes;

  const OfficialDocCategory({
    required this.id,
    required this.order,
    required this.title,
    required this.subtitle,
    required this.audience,
    required this.icon,
    required this.color,
    this.scopes = const [DocRegulationScope.ortakMevzuat],
  });
}

/// Matbu Evrak Şablonu tanımı
class OfficialDocTemplate {
  final String id;
  final String code; // ör. "1.1", "10.1", "12.1"
  final String categoryId;
  final String title;
  final String subtitle;
  final String legalBasis; // Yönetmelik ve Madde Dayanağı
  final List<DocRegulationScope> scopes;
  final DocAudience audience;
  final DocLayoutKind layoutKind;
  final DocHeaderStyle defaultHeaderStyle;
  final IconData icon;
  final bool usesStaffSignatureSelector;
  final List<String>? customStudentTableHeaders;
  final List<String> Function(
    int index,
    DocStudentItem s,
    Map<String, dynamic> answers,
  )? customStudentRowBuilder;
  final List<DocQuestionField> questions;
  final String Function(Map<String, dynamic> answers, SchoolDocContext ctx) composeBody;
  final List<MapEntry<String, String>> Function(Map<String, dynamic> answers, SchoolDocContext ctx)? buildMetaRows;
  final List<DocSigner> Function(Map<String, dynamic> answers, SchoolDocContext ctx)? buildSigners;

  const OfficialDocTemplate({
    required this.id,
    required this.code,
    required this.categoryId,
    required this.title,
    required this.subtitle,
    this.legalBasis = '',
    this.scopes = const [DocRegulationScope.ortakMevzuat],
    required this.audience,
    required this.layoutKind,
    required this.defaultHeaderStyle,
    required this.icon,
    this.usesStaffSignatureSelector = false,
    this.customStudentTableHeaders,
    this.customStudentRowBuilder,
    required this.questions,
    required this.composeBody,
    this.buildMetaRows,
    this.buildSigners,
  });
}

/// Okuldan otomatik çekilen bağlam verileri
class SchoolDocContext {
  final String institutionId;
  final String schoolTypeId;
  final String schoolName;
  final String schoolTypeName;
  final String city;
  final String district;
  final String address;
  final String phone;
  final String email;
  final String? logoUrl;
  final String academicYear; // ör. "2026-2027"
  final String activeTermLabel; // ör. "1. Dönem"
  final String principalName;
  final String principalTitle;
  final List<DocStaffItem> vicePrincipals;
  final List<DocStaffItem> counselors;
  final List<DocStaffItem> allStaff;
  final List<DocClassItem> classes;
  final List<String> branches; // Branş listesi
  final Map<String, List<String>> classTeachersByClass; // className -> derse giren öğretmen adları
  final DocStaffItem? currentUser;

  const SchoolDocContext({
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolName,
    required this.schoolTypeName,
    this.city = '',
    this.district = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.logoUrl,
    required this.academicYear,
    required this.activeTermLabel,
    this.principalName = 'Okul Müdürü',
    this.principalTitle = 'Okul Müdürü',
    this.vicePrincipals = const [],
    this.counselors = const [],
    this.allStaff = const [],
    this.classes = const [],
    this.branches = const [],
    this.classTeachersByClass = const {},
    this.currentUser,
  });

  SchoolDocContext copyWith({
    String? schoolName,
    String? city,
    String? district,
    String? principalName,
    String? principalTitle,
  }) {
    return SchoolDocContext(
      institutionId: institutionId,
      schoolTypeId: schoolTypeId,
      schoolName: schoolName ?? this.schoolName,
      schoolTypeName: schoolTypeName,
      city: city ?? this.city,
      district: district ?? this.district,
      address: address,
      phone: phone,
      email: email,
      logoUrl: logoUrl,
      academicYear: academicYear,
      activeTermLabel: activeTermLabel,
      principalName: principalName ?? this.principalName,
      principalTitle: principalTitle ?? this.principalTitle,
      vicePrincipals: vicePrincipals,
      counselors: counselors,
      allStaff: allStaff,
      classes: classes,
      branches: branches,
      classTeachersByClass: classTeachersByClass,
      currentUser: currentUser,
    );
  }
}

class DocStaffItem {
  final String id;
  final String fullName;
  final String role;
  final String branch;
  final String phone;
  final bool isCustom;

  const DocStaffItem({
    required this.id,
    required this.fullName,
    this.role = '',
    this.branch = '',
    this.phone = '',
    this.isCustom = false,
  });

  static String? _normalizeRoleOrSlug(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == '-') return null;
    final rl = s.toLowerCase().replaceAll('I', 'ı').replaceAll('İ', 'i');
    if (rl == 'mudur_yardimcisi' ||
        rl == 'manager' ||
        rl.contains('mudur yardimcisi') ||
        rl.contains('mudur_yardimcisi') ||
        rl.contains('müdür yardımcısı')) {
      return 'İdare / Müdür Yardımcısı';
    }
    if (rl == 'mudur' ||
        rl == 'müdür' ||
        rl == 'principal' ||
        rl == 'okul_muduru' ||
        rl == 'okul muduru' ||
        rl == 'okul müdürü' ||
        rl == 'admin' ||
        rl == 'genel_mudur' ||
        rl == 'genel müdür') {
      return 'İdare / Okul Müdürü';
    }
    if (rl == 'counselor' ||
        rl == 'pdr' ||
        rl == 'rehber' ||
        rl == 'rehberlik' ||
        rl.contains('psikolojik')) {
      return 'Rehberlik ve Psikolojik Danışmanlık';
    }
    if (rl == 'teacher' || rl == 'ogretmen' || rl == 'öğretmen') {
      return 'Genel / Branşsız Öğretmen';
    }
    return null;
  }

  String get groupLabel {
    final b = branch.trim();
    if (b.isNotEmpty && b != '-') {
      final normalizedBranchSlug = _normalizeRoleOrSlug(b);
      if (normalizedBranchSlug != null) return normalizedBranchSlug;
      return b;
    }
    final normalizedRole = _normalizeRoleOrSlug(role);
    if (normalizedRole != null) return normalizedRole;
    final r = role.trim();
    return (r.isNotEmpty && r != '-') ? r : 'Öğretmen';
  }

  String get displayLabel => '$fullName ($groupLabel)';

  DocStaffItem copyWith({
    String? id,
    String? fullName,
    String? role,
    String? branch,
    String? phone,
    bool? isCustom,
  }) {
    return DocStaffItem(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      branch: branch ?? this.branch,
      phone: phone ?? this.phone,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'fullName': fullName,
    'role': role,
    'branch': branch,
    'phone': phone,
    'isCustom': isCustom,
  };

  factory DocStaffItem.fromMap(Map<String, dynamic> m) => DocStaffItem(
    id: (m['id'] ?? '').toString(),
    fullName: (m['fullName'] ?? '').toString(),
    role: (m['role'] ?? '').toString(),
    branch: (m['branch'] ?? '').toString(),
    phone: (m['phone'] ?? '').toString(),
    isCustom: m['isCustom'] == true,
  );
}

class DocClassItem {
  final String id;
  final String className;
  final int classLevel;
  final String advisorTeacher;

  const DocClassItem({
    required this.id,
    required this.className,
    required this.classLevel,
    this.advisorTeacher = '',
  });
}

class DocStudentItem {
  final String id;
  final String fullName;
  final String studentNo;
  final String tcNo;
  final String className;
  final String parentName;
  final String parentPhone;

  const DocStudentItem({
    required this.id,
    required this.fullName,
    this.studentNo = '',
    this.tcNo = '',
    this.className = '',
    this.parentName = '',
    this.parentPhone = '',
  });

  String get displayLabel {
    final parts = <String>[
      if (studentNo.isNotEmpty) '$studentNo -',
      fullName,
      if (className.isNotEmpty) '($className)',
    ];
    return parts.join(' ');
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fullName': fullName,
        'studentNo': studentNo,
        'tcNo': tcNo,
        'className': className,
        'parentName': parentName,
        'parentPhone': parentPhone,
      };

  factory DocStudentItem.fromMap(Map<String, dynamic> m) => DocStudentItem(
        id: (m['id'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        studentNo: (m['studentNo'] ?? '').toString(),
        tcNo: (m['tcNo'] ?? '').toString(),
        className: (m['className'] ?? '').toString(),
        parentName: (m['parentName'] ?? '').toString(),
        parentPhone: (m['parentPhone'] ?? '').toString(),
      );
}

/// Üretilip kaydedilen resmi evrak kaydı (Aktif / Pasif arşiv destekli)
class SavedOfficialDocument {
  final String id;
  final String institutionId;
  final String schoolTypeId;
  final String templateId;
  final String categoryId;
  final String categoryTitle;
  final String title;
  final String documentSubject;
  final DocHeaderStyle headerStyle;
  final Map<String, dynamic> answers;
  final String composedBody;
  final List<DocSigner> signers;
  final DateTime createdAt;
  final String createdBy;
  final String creatorName;
  final bool isPassive; // true = Pasif (Arşiv), false = Aktif
  final bool isActive; // false = Silinmiş (soft-delete)

  const SavedOfficialDocument({
    this.id = '',
    required this.institutionId,
    required this.schoolTypeId,
    required this.templateId,
    required this.categoryId,
    required this.categoryTitle,
    required this.title,
    this.documentSubject = '',
    this.headerStyle = DocHeaderStyle.corporateLogo,
    this.answers = const {},
    required this.composedBody,
    this.signers = const [],
    required this.createdAt,
    required this.createdBy,
    required this.creatorName,
    this.isPassive = false,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
        'institutionId': institutionId,
        'schoolTypeId': schoolTypeId,
        'templateId': templateId,
        'categoryId': categoryId,
        'categoryTitle': categoryTitle,
        'title': title,
        'documentSubject': documentSubject,
        'headerStyle': headerStyle.name,
        'answers': answers,
        'composedBody': composedBody,
        'signers': signers.map((s) => s.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
        'creatorName': creatorName,
        'isPassive': isPassive,
        'isActive': isActive,
      };

  factory SavedOfficialDocument.fromMap(Map<String, dynamic> map, String docId) {
    final rawStyle = (map['headerStyle'] ?? '').toString();
    final style = DocHeaderStyle.values.firstWhere(
      (e) => e.name == rawStyle,
      orElse: () => DocHeaderStyle.corporateLogo,
    );
    final rawSigners = map['signers'];
    final parsedSigners = rawSigners is List
        ? rawSigners
            .whereType<Map>()
            .map((e) => DocSigner.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <DocSigner>[];

    DateTime date = DateTime.now();
    if (map['createdAt'] is Timestamp) {
      date = (map['createdAt'] as Timestamp).toDate();
    }

    return SavedOfficialDocument(
      id: docId,
      institutionId: (map['institutionId'] ?? '').toString(),
      schoolTypeId: (map['schoolTypeId'] ?? '').toString(),
      templateId: (map['templateId'] ?? '').toString(),
      categoryId: (map['categoryId'] ?? '').toString(),
      categoryTitle: (map['categoryTitle'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      documentSubject: (map['documentSubject'] ?? '').toString(),
      headerStyle: style,
      answers: map['answers'] is Map ? Map<String, dynamic>.from(map['answers'] as Map) : {},
      composedBody: (map['composedBody'] ?? '').toString(),
      signers: parsedSigners,
      createdAt: date,
      createdBy: (map['createdBy'] ?? '').toString(),
      creatorName: (map['creatorName'] ?? '').toString(),
      isPassive: map['isPassive'] == true,
      isActive: map['isActive'] ?? true,
    );
  }
}

/// Toplu Soruşturma / Vaka Dosyası (Tek PDF Birleştirici) içindeki tek bir evrak adımı
class DossierBundleItem {
  final OfficialDocTemplate template;
  final String documentTitle;
  final String stepDateLabel;
  final Map<String, dynamic> answers;
  final String composedBody;
  final List<DocSigner> signers;
  final List<DocStaffItem> signatureStaff;

  const DossierBundleItem({
    required this.template,
    required this.documentTitle,
    this.stepDateLabel = '',
    required this.answers,
    required this.composedBody,
    required this.signers,
    this.signatureStaff = const [],
  });
}

