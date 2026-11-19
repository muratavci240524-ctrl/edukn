import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';
import '../../../../services/official_document_context_service.dart';
import '../../../../services/official_document_pdf_service.dart';
import '../../../../services/web_share/web_file_share.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'official_document_catalog_oddk_disiplin.dart';

/// Tek öğrenci / olay kaydı üzerinden seçilen ÖDDK-01 .. ÖDDK-16 adımlarını
/// otomatik senkronize edip Kapak Sayfası + Dizi Pusulası + Tüm Resmi Evraklarla
/// TEK PDF VAKA DOSYASI olarak üreten ve arşivleyen sihirbaz ekranı.
class OddkBulkDossierScreen extends StatefulWidget {
  static const String bundleTemplateId = 'oddk_toplu_sorusturma_dosyasi';

  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final SavedOfficialDocument? existingDocument;
  final List<String>? allowedClassIds;

  const OddkBulkDossierScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.existingDocument,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<OddkBulkDossierScreen> createState() => _OddkBulkDossierScreenState();
}

class _OddkBulkDossierScreenState extends State<OddkBulkDossierScreen>
    with SingleTickerProviderStateMixin {
  final OfficialDocumentContextService _contextService =
      OfficialDocumentContextService();

  SchoolDocContext? _ctx;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  bool _isSaving = false;
  String _savedDocId = '';

  late TabController _mobileTabController;
  DocHeaderStyle _headerStyle = DocHeaderStyle.mebOfficial;
  bool _includeCoverAndIndex = true;
  bool _isHighSchoolMode =
      false; // false = İlköğretim ÖDDK, true = Lise Disiplin

  // Kurum ve Evrak Başlık Alanları
  final TextEditingController _dossierTitleController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _authorityNameController =
      TextEditingController();
  final TextEditingController _authorityTitleController =
      TextEditingController();

  // Ortak Vaka / Öğrenci / Olay Alanları
  final TextEditingController _fileNoController = TextEditingController();
  final TextEditingController _decisionNoController = TextEditingController();
  final TextEditingController _incidentDateController = TextEditingController();
  final TextEditingController _decisionDateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _incidentSummaryController =
      TextEditingController();
  final TextEditingController _parentNameController = TextEditingController();
  final TextEditingController _victimNameController = TextEditingController();
  final TextEditingController _witnessNameController = TextEditingController();

  String _selectedClass = '';
  String _selectedStudentLabel = '';
  String _advisorTeacher = '';
  String _boardChair = '';
  String _counselor = '';
  List<String> _boardMembers = [];
  String _finalVerdict = '';

  List<DocStudentItem> _classStudents = [];
  bool _loadingStudents = false;

  // Seçilen Adımlar (templateId seti) ve Adım Bazlı Durumlar
  final Set<String> _selectedStepIds = {};
  String _focusedStepId = '__cover__'; // '__cover__' veya template.id
  bool _showStepQuestions = false;

  final Map<String, Map<String, dynamic>> _stepAnswers = {};
  final Map<String, String> _manualStepBodies = {};
  final Map<String, List<DocSigner>> _manualStepSigners = {};
  final Map<String, String> _multiCheckSearch = {};
  final Map<String, List<String>> _customMultiCheckItems = {};

  final TextEditingController _activeBodyController = TextEditingController();

  List<OfficialDocTemplate> get _allSteps =>
      OfficialDocumentCatalogOddkDisiplin.templates;

  static const List<String> _ilkogretimVerdicts = [
    'Yaptırım / Ceza Verilmesine Yer Olmadığına — PDR Rehberlik Takibi ve Veli İş Birliği Uygulanmasına',
    'İlköğretim Md. 55/1-a Uyarınca "UYARMA" Yaptırımı Verilmesine (Yazılı Bildirim, e-Okul Siciline İşlenmez)',
    'İlköğretim Md. 55/1-b Uyarınca "KINAMA" Yaptırımı Verilmesine (İyi Hal İndirimi Değerlendirilerek)',
    'İlköğretim Md. 55/1-c Uyarınca "OKUL DEĞİŞTİRME" Yaptırım Teklifinin İlçe ÖDDK\'ya Gönderilmesine',
  ];

  static const List<String> _liseVerdicts = [
    'Yaptırım / Ceza Verilmesine Yer Olmadığına — PDR Rehberlik Takibi ve Veli İş Birliği Uygulanmasına',
    'Ortaöğretim Md. 164/1 Uyarınca "KINAMA" Cezası Verilmesine (-10 Davranış Puanı)',
    'Ortaöğretim Md. 164/2 Uyarınca "OKULDAN 1–5 GÜN KISA SÜRELİ UZAKLAŞTIRMA" Cezası Verilmesine (-20 Puan)',
    'Ortaöğretim Md. 164/3 Uyarınca "OKUL DEĞİŞTİRME" Teklifinin İlçe Disiplin Kuruluna Sunulmasına (-40 Puan)',
    'Ortaöğretim Md. 164/4 Uyarınca "ÖRGÜN EĞİTİM DIŞINA ÇIKARMA" Teklifinin İl Disiplin Kuruluna Sunulmasına (-80 Puan)',
  ];

  List<String> get _verdictOptions =>
      _isHighSchoolMode ? _liseVerdicts : _ilkogretimVerdicts;

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ç', 'ç')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ü', 'ü')
        .toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 3, vsync: this);
    _initScreen();
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
    _dossierTitleController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    _schoolNameController.dispose();
    _authorityNameController.dispose();
    _authorityTitleController.dispose();
    _fileNoController.dispose();
    _decisionNoController.dispose();
    _incidentDateController.dispose();
    _decisionDateController.dispose();
    _locationController.dispose();
    _incidentSummaryController.dispose();
    _parentNameController.dispose();
    _victimNameController.dispose();
    _witnessNameController.dispose();
    _activeBodyController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    setState(() => _isLoading = true);
    try {
      final ctx = await _contextService.loadContext(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        allowedClassIds: widget.allowedClassIds,
      );
      _ctx = ctx;

      final today = DateFormat('dd.MM.yyyy').format(DateTime.now());
      final nowTime = DateFormat('HH:mm').format(DateTime.now());
      final stNorm = _normTr(widget.schoolTypeName);
      _isHighSchoolMode =
          stNorm.contains('lise') ||
          stNorm.contains('anadolu') ||
          stNorm.contains('fen') ||
          stNorm.contains('ortaöğretim') ||
          stNorm.contains('ortaogretim');

      // Tüm 16 adımın varsayılan cevaplarını hazırla
      for (final step in _allSteps) {
        final map = <String, dynamic>{};
        for (final q in step.questions) {
          if (q.defaultValue != null) {
            if (q.defaultValue is List) {
              map[q.key] = List<String>.from(q.defaultValue as List);
            } else {
              map[q.key] = q.defaultValue;
            }
          }
        }
        _stepAnswers[step.id] = map;
      }

      // Ortak varsayılanlar
      _dossierTitleController.text = _isHighSchoolMode
          ? 'OKUL ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU SORUŞTURMA VAKA DOSYASI'
          : 'ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) VAKA DOSYASI';
      _provinceController.text = ctx.city;
      _districtController.text = ctx.district;
      _schoolNameController.text = ctx.schoolName;
      _authorityNameController.text = ctx.principalName;
      _authorityTitleController.text = ctx.principalTitle.isNotEmpty
          ? ctx.principalTitle
          : 'Okul Müdürü';

      final yearPrefix = ctx.academicYear.split('-').first;
      _fileNoController.text = _isHighSchoolMode
          ? '$yearPrefix / DİS-01'
          : '$yearPrefix / ÖDDK-01';
      _decisionNoController.text = 'Karar No: $yearPrefix/01';
      _incidentDateController.text = '$today - $nowTime';
      _decisionDateController.text = today;
      _locationController.text =
          'Okul Dersliği / Koridor Alanı (Güvenlik Kamerası Görüş Açısı)';
      _incidentSummaryController.text =
          'Okul içi düzen, ders işlenişi ve akran güvenliği kurallarına aykırı olarak gerçekleşen öğrenci davranışı / akran anlaşmazlığı olayı.';

      _boardChair = ctx.vicePrincipals.isNotEmpty
          ? ctx.vicePrincipals.first.fullName
          : '';
      _counselor = ctx.counselors.isNotEmpty
          ? ctx.counselors.first.fullName
          : '';
      _boardMembers = ctx.allStaff
          .where(
            (s) =>
                s.fullName != ctx.principalName &&
                s.fullName != _boardChair &&
                s.fullName != _counselor,
          )
          .take(3)
          .map((s) => s.fullName)
          .toList();

      _finalVerdict = _verdictOptions[1];

      // Varsayılan olarak tüm 16 adımı seç
      for (final s in _allSteps) {
        _selectedStepIds.add(s.id);
      }

      // Eğer kayıtlı bir toplu vaka dosyası açılıyorsa geri yükle
      final existing = widget.existingDocument;
      if (existing != null) {
        _savedDocId = existing.id;
        _headerStyle = existing.headerStyle;
        if (existing.title.trim().isNotEmpty) {
          _dossierTitleController.text = existing.title;
        }
        _restoreFromSavedAnswers(existing.answers);
      } else if (ctx.classes.isNotEmpty) {
        _selectedClass = ctx.classes.first.className;
        if (ctx.classes.first.advisorTeacher.trim().isNotEmpty) {
          _advisorTeacher = ctx.classes.first.advisorTeacher.trim();
        } else if (ctx.currentUser != null) {
          _advisorTeacher = ctx.currentUser!.fullName;
        }
      }

      if (_selectedClass.isNotEmpty) {
        await _loadClassStudents(
          _selectedClass,
          autoPickFirst: existing == null,
        );
      }

      _syncSharedFieldsToAllSteps();
      _refreshFocusedBodyController();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _restoreFromSavedAnswers(Map<String, dynamic> data) {
    _includeCoverAndIndex = data['includeCoverAndIndex'] != false;
    _isHighSchoolMode = data['isHighSchoolMode'] == true;
    _provinceController.text =
        (data['customProvince'] ?? _provinceController.text).toString();
    _districtController.text =
        (data['customDistrict'] ?? _districtController.text).toString();
    _schoolNameController.text =
        (data['customSchoolName'] ?? _schoolNameController.text).toString();
    _authorityNameController.text =
        (data['authorityName'] ?? _authorityNameController.text).toString();
    _authorityTitleController.text =
        (data['authorityTitle'] ?? _authorityTitleController.text).toString();

    _fileNoController.text = (data['fileNo'] ?? _fileNoController.text)
        .toString();
    _decisionNoController.text =
        (data['decisionNo'] ?? _decisionNoController.text).toString();
    _incidentDateController.text =
        (data['incidentDate'] ?? _incidentDateController.text).toString();
    _decisionDateController.text =
        (data['decisionDate'] ?? _decisionDateController.text).toString();
    _locationController.text = (data['location'] ?? _locationController.text)
        .toString();
    _incidentSummaryController.text =
        (data['incidentSummary'] ?? _incidentSummaryController.text).toString();
    _parentNameController.text =
        (data['parentName'] ?? _parentNameController.text).toString();
    _victimNameController.text =
        (data['victimName'] ?? _victimNameController.text).toString();
    _witnessNameController.text =
        (data['witnessName'] ?? _witnessNameController.text).toString();

    _selectedClass = (data['selectedClass'] ?? '').toString();
    _selectedStudentLabel = (data['selectedStudentLabel'] ?? '').toString();
    _advisorTeacher = (data['advisorTeacher'] ?? _advisorTeacher).toString();
    _boardChair = (data['boardChair'] ?? _boardChair).toString();
    _counselor = (data['counselor'] ?? _counselor).toString();
    if (data['boardMembers'] is List) {
      _boardMembers = List<String>.from(
        (data['boardMembers'] as List).map((e) => e.toString()),
      );
    }
    final savedVerdict = (data['finalVerdict'] ?? '').toString();
    if (savedVerdict.isNotEmpty) {
      _finalVerdict = savedVerdict;
    }

    if (data['selectedStepIds'] is List) {
      _selectedStepIds
        ..clear()
        ..addAll((data['selectedStepIds'] as List).map((e) => e.toString()));
    }

    if (data['stepAnswers'] is Map) {
      final rawMap = Map<String, dynamic>.from(data['stepAnswers'] as Map);
      rawMap.forEach((stepId, val) {
        if (val is Map) {
          _stepAnswers[stepId] = Map<String, dynamic>.from(val);
        }
      });
    }

    if (data['manualStepBodies'] is Map) {
      final rawBodies = Map<String, dynamic>.from(
        data['manualStepBodies'] as Map,
      );
      rawBodies.forEach((k, v) {
        if (v != null && v.toString().trim().isNotEmpty) {
          _manualStepBodies[k] = v.toString();
        }
      });
    }

    if (data['manualStepSigners'] is Map) {
      final rawSigners = Map<String, dynamic>.from(
        data['manualStepSigners'] as Map,
      );
      rawSigners.forEach((k, v) {
        if (v is List) {
          _manualStepSigners[k] = v
              .whereType<Map>()
              .map((m) => DocSigner.fromMap(Map<String, dynamic>.from(m)))
              .toList();
        }
      });
    }
  }

  Future<void> _loadClassStudents(
    String className, {
    bool autoPickFirst = false,
  }) async {
    final ctx = _ctx;
    if (ctx == null || className.trim().isEmpty) return;
    final clsItem = ctx.classes.where((c) => c.className == className).toList();
    if (clsItem.isEmpty) return;

    if (clsItem.first.advisorTeacher.trim().isNotEmpty &&
        _advisorTeacher.trim().isEmpty) {
      _advisorTeacher = clsItem.first.advisorTeacher.trim();
    }

    setState(() => _loadingStudents = true);
    try {
      final list = await _contextService.loadStudentsForClasses(
        institutionId: widget.institutionId,
        targetClasses: clsItem,
      );
      _classStudents = list;
      if (autoPickFirst && list.isNotEmpty) {
        _applyPrimaryStudent(list.first);
      }
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  void _applyPrimaryStudent(DocStudentItem s) {
    _selectedStudentLabel = s.displayLabel;
    if (s.parentName.trim().isNotEmpty || s.parentPhone.trim().isNotEmpty) {
      final parts = <String>[
        if (s.parentName.trim().isNotEmpty) s.parentName.trim(),
        if (s.parentPhone.trim().isNotEmpty) s.parentPhone.trim(),
      ];
      _parentNameController.text = parts.join(' — ');
    }
  }

  SchoolDocContext _effectiveContext() {
    final base = _ctx!;
    return base.copyWith(
      city: _provinceController.text.trim(),
      district: _districtController.text.trim(),
      schoolName: _schoolNameController.text.trim().isNotEmpty
          ? _schoolNameController.text.trim()
          : base.schoolName,
      principalName: _authorityNameController.text.trim().isNotEmpty
          ? _authorityNameController.text.trim()
          : base.principalName,
      principalTitle: _authorityTitleController.text.trim().isNotEmpty
          ? _authorityTitleController.text.trim()
          : 'Okul Müdürü',
    );
  }

  String get _boardOfficialHeading => _isHighSchoolMode
      ? 'OKUL ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU BAŞKANLIĞINA'
      : 'ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) BAŞKANLIĞINA';

  String get _boardDisplayName => _isHighSchoolMode
      ? 'Okul Öğrenci Ödül ve Disiplin Kurulu'
      : 'Öğrenci Davranışlarını Değerlendirme Kurulu (ÖDDK)';

  /// Ortak vaka formundaki tüm bilgileri 16 adımın ilgili soru anahtarlarına senkronize eder
  void _syncSharedFieldsToAllSteps() {
    final fileNo = _fileNoController.text.trim();
    final decisionNo = _decisionNoController.text.trim();
    final incDate = _incidentDateController.text.trim();
    final decDate = _decisionDateController.text.trim();
    final loc = _locationController.text.trim();
    final summary = _incidentSummaryController.text.trim();
    final cls = _selectedClass.trim();
    final stu = _selectedStudentLabel.trim().isNotEmpty
        ? _selectedStudentLabel.trim()
        : '................................';
    final parentFull = _parentNameController.text.trim();
    final parentClean = parentFull.contains('—')
        ? parentFull.split('—').first.trim()
        : parentFull;
    final victim = _victimNameController.text.trim();
    final witness = _witnessNameController.text.trim();

    final involvedList = <String>[
      if (_selectedStudentLabel.trim().isNotEmpty) _selectedStudentLabel.trim(),
      if (victim.isNotEmpty) victim,
    ];

    for (final step in _allSteps) {
      final a = _stepAnswers.putIfAbsent(step.id, () => <String, dynamic>{});

      // Ortak Şube & Dosya No
      if (_hasQuestion(step, 'targetClass')) a['targetClass'] = cls;
      if (_hasQuestion(step, 'fileNo')) {
        a['fileNo'] = step.id == 'oddk_11_pdr_vaka_inceleme_kanaat_raporu'
            ? '$fileNo (GİZLİ)'
            : fileNo;
      }

      // Öğrenci Atamaları
      if (step.id == 'oddk_07_magdur_sikayetci_ifade_tutanagi') {
        a['student'] = victim.isNotEmpty
            ? victim
            : '................................';
      } else if (_hasQuestion(step, 'student')) {
        a['student'] = stu;
      }

      if (_hasQuestion(step, 'students')) {
        if (step.id == 'oddk_06_mudurluk_inceleme_ve_kurula_havale') {
          a['students'] = [stu];
        } else {
          a['students'] = involvedList.isNotEmpty ? involvedList : [stu];
        }
      }

      if (step.id == 'oddk_08_gorgu_tanigi_ifade_tutanagi' &&
          witness.isNotEmpty) {
        a['manualWitnessName'] = witness;
      }

      // Veli Bilgileri
      if (parentFull.isNotEmpty) {
        if (step.id == 'oddk_03_veli_onlem_gorusme_gelmeme_tutanagi') {
          a['parentName'] = parentFull;
        } else if (step.id == 'oddk_10_veli_bilgilendirme_ve_beyan_tutanagi' ||
            step.id == 'oddk_15_karar_veli_sonuc_tebligati') {
          a['parentName'] = parentClean;
        }
      }

      // Tarih & Saat Senkronizasyonu
      if (step.id == 'oddk_12_kurul_toplanti_cagrisi_ve_teblig') {
        a['meetingDate'] = '$decDate - Saat 15:15';
      } else if (step.id == 'oddk_14_kurul_gerekceli_karar_tutanagi' ||
          step.id == 'oddk_15_karar_veli_sonuc_tebligati' ||
          step.id == 'oddk_16_izleme_ceza_kaldirma_ve_dizi_pusulasi') {
        a['date'] = decDate;
      } else if (_hasQuestion(step, 'date') && incDate.isNotEmpty) {
        a['date'] = incDate;
      }

      // Olay Yeri ve Özeti
      if (_hasQuestion(step, 'location') && loc.isNotEmpty) {
        a['location'] = loc;
      }
      if (summary.isNotEmpty) {
        if (step.id == 'oddk_04_ayrintili_olay_delil_kamera_tutanagi') {
          a['narrative'] = summary;
        } else if (step.id == 'oddk_05_ogretmen_oddk_sevk_raporu') {
          a['referralReason'] = summary;
        } else if (step.id == 'oddk_07_magdur_sikayetci_ifade_tutanagi' ||
            step.id == 'oddk_08_gorgu_tanigi_ifade_tutanagi') {
          a['incidentTopic'] = loc.isNotEmpty ? '$loc — $summary' : summary;
        } else if (step.id == 'oddk_09_ogrenci_yazili_savunma_tutanagi') {
          a['allegation'] = summary;
        }
      }

      // Kurul Türü ve Görevli Personeller
      if (step.id == 'oddk_06_mudurluk_inceleme_ve_kurula_havale') {
        a['boardName'] = _boardOfficialHeading;
      } else if (step.id == 'oddk_12_kurul_toplanti_cagrisi_ve_teblig') {
        a['boardType'] = _boardDisplayName;
      } else if (step.id == 'oddk_14_kurul_gerekceli_karar_tutanagi') {
        a['boardName'] = _isHighSchoolMode
            ? 'Okul Öğrenci Ödül ve Disiplin Kurulu (Ortaöğretim Md. 164)'
            : 'Öğrenci Davranışlarını Değerlendirme Kurulu (İlköğretim Md. 55)';
        a['decisionNo'] = '$decisionNo (Dosya: $fileNo)';
        if (_finalVerdict.isNotEmpty) {
          a['finalVerdict'] = _finalVerdict;
        }
      } else if (step.id == 'oddk_15_karar_veli_sonuc_tebligati') {
        a['docNo'] = '$fileNo / $decisionNo';
        if (_finalVerdict.isNotEmpty) {
          a['decisionSummary'] =
              'Kurumumuz $_boardDisplayName\'nun $decDate tarihli ve "$decisionNo" sayılı kararı ile öğrencimiz hakkında: "$_finalVerdict" yönünde karar tesis edilmiştir.';
        }
      } else if (step.id == 'oddk_16_izleme_ceza_kaldirma_ve_dizi_pusulasi') {
        a['docMode'] =
            '2) ÖDDK / Disiplin Soruşturma Dosyası Resmi Dizi Pusulası ve Kapanış Tutanağı';
      }

      if (_hasQuestion(step, 'teacher') && _advisorTeacher.isNotEmpty) {
        a['teacher'] = _advisorTeacher;
      }
      if (_boardChair.isNotEmpty) {
        if (_hasQuestion(step, 'boardChair')) a['boardChair'] = _boardChair;
        if (_hasQuestion(step, 'interviewer')) a['interviewer'] = _boardChair;
        if (_hasQuestion(step, 'chair')) a['chair'] = _boardChair;
      }
      if (_counselor.isNotEmpty) {
        if (_hasQuestion(step, 'counselor')) a['counselor'] = _counselor;
        if (_hasQuestion(step, 'observer')) a['observer'] = _counselor;
      }
      if (_boardMembers.isNotEmpty) {
        if (_hasQuestion(step, 'boardMembers')) {
          a['boardMembers'] = List<String>.from(_boardMembers);
        }
        if (_hasQuestion(step, 'member')) {
          a['member'] = _boardMembers.first;
        }
      }
      if (step.id == 'oddk_03_veli_onlem_gorusme_gelmeme_tutanagi') {
        a['staffParticipants'] = <String>[
          if (_advisorTeacher.isNotEmpty) _advisorTeacher,
          if (_counselor.isNotEmpty) _counselor,
        ];
      }
      if (step.id == 'oddk_04_ayrintili_olay_delil_kamera_tutanagi') {
        final reps = <String>[
          if (_advisorTeacher.isNotEmpty) _advisorTeacher,
          if (_boardChair.isNotEmpty) _boardChair,
        ];
        if (reps.isNotEmpty) a['reporters'] = reps;
      }
    }
  }

  bool _hasQuestion(OfficialDocTemplate t, String key) =>
      t.questions.any((q) => q.key == key);

  String _composedBodyForStep(OfficialDocTemplate step) {
    if (_manualStepBodies.containsKey(step.id)) {
      return _manualStepBodies[step.id]!;
    }
    final effCtx = _effectiveContext();
    final a = _stepAnswers[step.id] ?? const <String, dynamic>{};
    return step.composeBody(a, effCtx);
  }

  List<DocSigner> _signersForStep(OfficialDocTemplate step) {
    if (_manualStepSigners.containsKey(step.id)) {
      return _manualStepSigners[step.id]!;
    }
    final effCtx = _effectiveContext();
    final a = _stepAnswers[step.id] ?? const <String, dynamic>{};
    return step.buildSigners?.call(a, effCtx) ?? const [];
  }

  List<DocStaffItem> _signatureStaffForMeetingCall() {
    final ctx = _ctx;
    if (ctx == null) return const [];
    final names = <String>{
      if (_boardChair.trim().isNotEmpty) _boardChair.trim(),
      ..._boardMembers.map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (_counselor.trim().isNotEmpty) _counselor.trim(),
      if (_advisorTeacher.trim().isNotEmpty) _advisorTeacher.trim(),
    };
    final result = <DocStaffItem>[];
    for (final name in names) {
      final found = ctx.allStaff.where((s) => s.fullName == name).toList();
      if (found.isNotEmpty) {
        result.add(found.first);
      } else {
        result.add(
          DocStaffItem(
            id: 'custom_$name',
            fullName: name,
            branch: 'Kurul Üyesi',
          ),
        );
      }
    }
    return result.isNotEmpty ? result : ctx.allStaff;
  }

  void _refreshFocusedBodyController() {
    if (_focusedStepId == '__cover__') return;
    final step = _allSteps.where((s) => s.id == _focusedStepId).toList();
    if (step.isEmpty) return;
    _activeBodyController.text = _composedBodyForStep(step.first);
  }

  void _onSharedFieldChanged() {
    setState(() {
      _syncSharedFieldsToAllSteps();
      _refreshFocusedBodyController();
    });
  }

  void _applyPreset(int presetIndex) {
    setState(() {
      _selectedStepIds.clear();
      switch (presetIndex) {
        case 0: // Tam 16 Adım
          for (final s in _allSteps) {
            _selectedStepIds.add(s.id);
          }
          break;
        case 1: // Önleyici Rehberlik & Sözleşme (01–03)
          _selectedStepIds.addAll([
            'oddk_01_sozlu_uyari_yapici_gorusme',
            'oddk_02_ek9_ogrenci_sozlesmesi',
            'oddk_03_veli_onlem_gorusme_gelmeme_tutanagi',
          ]);
          break;
        case 2: // Soruşturma, İfade, Savunma & PDR (04–11)
          for (int i = 3; i <= 10; i++) {
            _selectedStepIds.add(_allSteps[i].id);
          }
          break;
        case 3: // Kurul Karar, Tebligat & Kapanış (12–16)
          for (int i = 11; i < _allSteps.length; i++) {
            _selectedStepIds.add(_allSteps[i].id);
          }
          break;
        case 4: // Doğrudan Ağır Disiplin Vakası (Sözleşme Aşaması Aranmayan)
          _selectedStepIds.addAll([
            'oddk_04_ayrintili_olay_delil_kamera_tutanagi',
            'oddk_06_mudurluk_inceleme_ve_kurula_havale',
            'oddk_07_magdur_sikayetci_ifade_tutanagi',
            'oddk_08_gorgu_tanigi_ifade_tutanagi',
            'oddk_09_ogrenci_yazili_savunma_tutanagi',
            'oddk_10_veli_bilgilendirme_ve_beyan_tutanagi',
            'oddk_11_pdr_vaka_inceleme_kanaat_raporu',
            'oddk_12_kurul_toplanti_cagrisi_ve_teblig',
            'oddk_14_kurul_gerekceli_karar_tutanagi',
            'oddk_15_karar_veli_sonuc_tebligati',
            'oddk_16_izleme_ceza_kaldirma_ve_dizi_pusulasi',
          ]);
          break;
      }
    });
  }

  List<DossierBundleItem> _buildSelectedBundleItems() {
    final orderedSteps = _allSteps
        .where((s) => _selectedStepIds.contains(s.id))
        .toList();
    final sigStaff = _signatureStaffForMeetingCall();

    return orderedSteps.map((step) {
      final a = Map<String, dynamic>.from(
        _stepAnswers[step.id] ?? const <String, dynamic>{},
      );
      final dateStr =
          (a['date'] ?? a['meetingDate'] ?? _incidentDateController.text)
              .toString();
      return DossierBundleItem(
        template: step,
        documentTitle: step.title.contains(':')
            ? step.title.split(':').sublist(1).join(':').trim()
            : step.title,
        stepDateLabel: dateStr,
        answers: a,
        composedBody: _composedBodyForStep(step),
        signers: _signersForStep(step),
        signatureStaff: step.usesStaffSignatureSelector ? sigStaff : const [],
      );
    }).toList();
  }

  List<DocSigner> _buildCoverSigners() {
    final effCtx = _effectiveContext();
    return [
      DocSigner(
        name: _boardChair.trim().isNotEmpty
            ? _boardChair.trim()
            : 'Kurul Başkanı',
        title: '$_boardDisplayName Başkanı',
      ),
      if (_counselor.trim().isNotEmpty)
        DocSigner(name: _counselor.trim(), title: 'Rehber Öğretmen / PDR'),
      DocSigner(
        name: effCtx.principalName,
        title: 'ONAY / ${effCtx.principalTitle}',
        isApproval: true,
      ),
    ];
  }

  Future<String?> _persistBundle({bool showFeedback = true}) async {
    if (_ctx == null) return null;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final effCtx = _effectiveContext();
      final items = _buildSelectedBundleItems();

      final summaryBody = StringBuffer()
        ..writeln(
          'TOPLU SORUŞTURMA / ÖDDK VAKA DOSYASI (${items.length} Resmi Evrak)',
        )
        ..writeln(
          'Dosya No: ${_fileNoController.text.trim()} | Öğrenci: $_selectedStudentLabel ($_selectedClass)',
        )
        ..writeln('Olay Özeti: ${_incidentSummaryController.text.trim()}')
        ..writeln(
          'İçerdiği Evraklar: ${items.map((e) => e.template.code).join(", ")}',
        );

      final payloadAnswers = <String, dynamic>{
        'includeCoverAndIndex': _includeCoverAndIndex,
        'isHighSchoolMode': _isHighSchoolMode,
        'customProvince': _provinceController.text.trim(),
        'customDistrict': _districtController.text.trim(),
        'customSchoolName': _schoolNameController.text.trim(),
        'authorityName': _authorityNameController.text.trim(),
        'authorityTitle': _authorityTitleController.text.trim(),
        'fileNo': _fileNoController.text.trim(),
        'decisionNo': _decisionNoController.text.trim(),
        'incidentDate': _incidentDateController.text.trim(),
        'decisionDate': _decisionDateController.text.trim(),
        'location': _locationController.text.trim(),
        'incidentSummary': _incidentSummaryController.text.trim(),
        'parentName': _parentNameController.text.trim(),
        'victimName': _victimNameController.text.trim(),
        'witnessName': _witnessNameController.text.trim(),
        'selectedClass': _selectedClass,
        'selectedStudentLabel': _selectedStudentLabel,
        'advisorTeacher': _advisorTeacher,
        'boardChair': _boardChair,
        'counselor': _counselor,
        'boardMembers': _boardMembers,
        'finalVerdict': _finalVerdict,
        'selectedStepIds': _selectedStepIds.toList(),
        'stepAnswers': _stepAnswers,
        'manualStepBodies': _manualStepBodies,
        'manualStepSigners': _manualStepSigners.map(
          (k, v) => MapEntry(k, v.map((s) => s.toMap()).toList()),
        ),
      };

      final studentShort = _selectedStudentLabel.trim().isNotEmpty
          ? ' — ${_selectedStudentLabel.split("(").first.trim()}'
          : '';
      final savedTitle =
          'Toplu Vaka Dosyası (${_fileNoController.text.trim()})$studentShort';

      final doc = SavedOfficialDocument(
        id: _savedDocId,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        templateId: OddkBulkDossierScreen.bundleTemplateId,
        categoryId: OfficialDocumentCatalogOddkDisiplin.category.id,
        categoryTitle:
            'Toplu ÖDDK / Disiplin Vaka Dosyası (${items.length} Evrak)',
        title: savedTitle,
        documentSubject: _dossierTitleController.text.trim(),
        headerStyle: _headerStyle,
        answers: payloadAnswers,
        composedBody: summaryBody.toString().trim(),
        signers: _buildCoverSigners(),
        createdAt: widget.existingDocument?.createdAt ?? DateTime.now(),
        createdBy: user?.uid ?? '',
        creatorName:
            effCtx.currentUser?.fullName ?? (user?.email ?? 'Kullanıcı'),
        isPassive: widget.existingDocument?.isPassive ?? false,
      );

      final id = await _contextService.saveDocument(doc);
      _savedDocId = id;
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Toplu soruşturma vaka dosyası arşive kaydedildi. Hazırlanan Evraklar sekmesinden tekrar açabilirsiniz.',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
      return id;
    } catch (e) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportCombinedPdf({required bool downloadOnly}) async {
    if (_ctx == null) return;
    final items = _buildSelectedBundleItems();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen dosyaya eklenecek en az 1 ÖDDK adımı seçiniz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);
    Uint8List? pdfBytes;
    try {
      final effCtx = _effectiveContext();
      pdfBytes = await OfficialDocumentPdfService.generateDossierBundle(
        ctx: effCtx,
        headerStyle: _headerStyle,
        customProvince: _provinceController.text,
        customDistrict: _districtController.text,
        customSchoolName: _schoolNameController.text,
        dossierTitle: _dossierTitleController.text.trim().isNotEmpty
            ? _dossierTitleController.text.trim()
            : 'ÖDDK VE DİSİPLİN SORUŞTURMA VAKA DOSYASI',
        fileNo: _fileNoController.text.trim(),
        boardName: _boardDisplayName,
        studentDisplay: _selectedStudentLabel.trim().isNotEmpty
            ? _selectedStudentLabel.trim()
            : '................................',
        className: _selectedClass,
        parentDisplay: _parentNameController.text.trim(),
        incidentDate: _incidentDateController.text.trim(),
        incidentLocation: _locationController.text.trim(),
        incidentSummary: _incidentSummaryController.text.trim(),
        finalVerdict: _finalVerdict,
        includeCoverAndIndex: _includeCoverAndIndex,
        coverSigners: _buildCoverSigners(),
        items: items,
        students: _classStudents,
      );
      unawaited(_persistBundle(showFeedback: false));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Birleşik PDF oluşturulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }

    if (pdfBytes != null) {
      final stuPart = _selectedStudentLabel.trim().isNotEmpty
          ? _selectedStudentLabel.split('(').first.trim()
          : 'Ogrenci';
      final fileName = sanitizeFileName(
        'ODDK_Toplu_Vaka_Dosyasi_${_fileNoController.text.trim()}_$stuPart.pdf',
      );
      if (downloadOnly) {
        await downloadFileUniversal(bytes: pdfBytes, fileName: fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$fileName (${items.length} resmi evrak birleşik) indirildi.',
              ),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
      } else {
        await printFileUniversal(bytes: pdfBytes, fileName: fileName);
      }
    }
  }

  Future<void> _exportSingleStepPdf(OfficialDocTemplate step) async {
    if (_ctx == null) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final effCtx = _effectiveContext();
      final bytes = await OfficialDocumentPdfService.generate(
        template: step,
        ctx: effCtx,
        headerStyle: _headerStyle,
        customProvince: _provinceController.text,
        customDistrict: _districtController.text,
        customSchoolName: _schoolNameController.text,
        documentTitle: step.title.contains(':')
            ? step.title.split(':').sublist(1).join(':').trim()
            : step.title,
        answers: _stepAnswers[step.id] ?? const {},
        composedBody: _composedBodyForStep(step),
        signers: _signersForStep(step),
        students: _classStudents,
        signatureStaff: step.usesStaffSignatureSelector
            ? _signatureStaffForMeetingCall()
            : const [],
      );
      final fileName = sanitizeFileName('${step.code}_${step.title}.pdf');
      await downloadFileUniversal(bytes: bytes, fileName: fileName);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANA EKRAN GÖRÜNÜMÜ
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1020;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: 'Toplu Soruşturma Vaka Dosyası Üretici',
        subtitle:
            'ÖDDK-01 .. ÖDDK-16 • Tek Öğrenci/Olay Girişiyle Birleşik Tek PDF Vaka Paketi',
        actions: [
          if (!_isLoading)
            IconButton(
              tooltip: 'Vaka Dosyasını Arşive Kaydet',
              onPressed: _isSaving
                  ? null
                  : () => _persistBundle(showFeedback: true),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.bookmark_added_outlined,
                      color: Color(0xFF991B1B),
                    ),
            ),
        ],
        bottom: !isWide
            ? TabBar(
                controller: _mobileTabController,
                labelColor: const Color(0xFF991B1B),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF991B1B),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.8,
                ),
                tabs: [
                  const Tab(text: '1. ORTAK VAKA'),
                  Tab(text: '2. ADIMLAR (${_selectedStepIds.length}/16)'),
                  const Tab(text: '3. ÖNİZLEME & PDF'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (width * 0.36).clamp(450.0, 620.0),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 24),
                    children: [
                      _buildSharedCaseCard(),
                      const SizedBox(height: 12),
                      _buildStepSelectorCard(isMobile: false),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                Expanded(child: _buildRightPreviewPane()),
              ],
            )
          : TabBarView(
              controller: _mobileTabController,
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  children: [_buildSharedCaseCard()],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                  children: [_buildStepSelectorCard(isMobile: true)],
                ),
                _buildRightPreviewPane(),
              ],
            ),
      bottomNavigationBar: _isLoading ? null : _buildBottomActionBar(isWide),
    );
  }

  Widget _buildBottomActionBar(bool isWide) {
    final count = _selectedStepIds.length;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 20 : 10,
        vertical: isWide ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: !isWide
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGeneratingPdf
                          ? null
                          : () => _exportCombinedPdf(downloadOnly: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A8A),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text(
                        'Önizle / Yazdır',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingPdf
                          ? null
                          : () => _exportCombinedPdf(downloadOnly: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF991B1B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                      label: Text(
                        'Tek PDF İndir ($count)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.folder_special_rounded,
                                size: 15,
                                color: Color(0xFF991B1B),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${_includeCoverAndIndex ? "Kapak + Dizi Pusulası + " : ""}$count Resmi Evrak Seçili',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isGeneratingPdf
                            ? null
                            : () => _exportCombinedPdf(downloadOnly: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E3A8A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.print_rounded, size: 17),
                        label: const Text(
                          'Birleşik PDF Yazdır / Önizle',
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isGeneratingPdf
                            ? null
                            : () => _exportCombinedPdf(downloadOnly: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF991B1B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _isGeneratingPdf
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 17,
                              ),
                        label: Text(
                          'Tek PDF Vaka Dosyası İndir ($count Evrak)',
                          style: const TextStyle(
                            fontSize: 12.3,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOL PANEL 1: ORTAK VAKA, ÖĞRENCİ, OLAY VE KURUL KÜNYESİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSharedCaseCard() {
    final ctx = _ctx!;
    final staffNames = ctx.allStaff.map((s) => s.fullName).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF991B1B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. Ortak Vaka & Öğrenci Künyesi',
                      style: GoogleFonts.inter(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const Text(
                      'Burada girdiğiniz bilgiler seçilen tüm ÖDDK evraklarına otomatik dağıtılır.',
                      style: TextStyle(
                        fontSize: 11.2,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),

          // Kademe / Mevzuat Seçimi
          const Text(
            'Mevzuat ve Kurul Türü',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: _buildModeChoice(
                  selected: !_isHighSchoolMode,
                  title: 'İlkokul / Ortaokul (ÖDDK)',
                  subtitle: 'İlköğretim Yön. Md. 53–61 & EK-9',
                  onTap: () {
                    setState(() {
                      _isHighSchoolMode = false;
                      _dossierTitleController.text =
                          'ÖĞRENCİ DAVRANIŞLARINI DEĞERLENDİRME KURULU (ÖDDK) VAKA DOSYASI';
                      if (!_verdictOptions.contains(_finalVerdict)) {
                        _finalVerdict = _verdictOptions[1];
                      }
                      _syncSharedFieldsToAllSteps();
                      _refreshFocusedBodyController();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChoice(
                  selected: _isHighSchoolMode,
                  title: 'Ortaöğretim / Lise Disiplin',
                  subtitle: 'Ortaöğretim Yön. Md. 163–178',
                  onTap: () {
                    setState(() {
                      _isHighSchoolMode = true;
                      _dossierTitleController.text =
                          'OKUL ÖĞRENCİ ÖDÜL VE DİSİPLİN KURULU SORUŞTURMA VAKA DOSYASI';
                      if (!_verdictOptions.contains(_finalVerdict)) {
                        _finalVerdict = _verdictOptions[1];
                      }
                      _syncSharedFieldsToAllSteps();
                      _refreshFocusedBodyController();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Antet & Kurum Özeti (Daraltılabilir)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            visualDensity: VisualDensity.compact,
            title: const Text(
              'Üst Antet, Kurum Adı ve Onay Makamı Ayarları',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3A8A),
              ),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      selected: _headerStyle == DocHeaderStyle.mebOfficial,
                      label: const Text('MEB Resmi Yazı Anteti'),
                      onSelected: (_) => setState(
                        () => _headerStyle = DocHeaderStyle.mebOfficial,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ChoiceChip(
                      selected: _headerStyle == DocHeaderStyle.corporateLogo,
                      label: const Text('Kurumsal Okul Anteti'),
                      onSelected: (_) => setState(
                        () => _headerStyle = DocHeaderStyle.corporateLogo,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _compactTextField(
                      controller: _provinceController,
                      label: 'İl',
                      onChanged: (_) => _onSharedFieldChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactTextField(
                      controller: _districtController,
                      label: 'İlçe',
                      onChanged: (_) => _onSharedFieldChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _compactTextField(
                controller: _schoolNameController,
                label: 'Resmi Okul / Kurum Adı',
                onChanged: (_) => _onSharedFieldChanged(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _compactTextField(
                      controller: _authorityNameController,
                      label: 'Onay Makamı (Müdür Adı)',
                      onChanged: (_) => _onSharedFieldChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactTextField(
                      controller: _authorityTitleController,
                      label: 'Onay Unvanı',
                      onChanged: (_) => _onSharedFieldChanged(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Dosya No & Tarihler
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  controller: _fileNoController,
                  label: 'Soruşturma Dosya No',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  controller: _decisionNoController,
                  label: 'Kurul Karar Sayısı',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  controller: _incidentDateController,
                  label: 'Olay / İlk İşlem Tarihi & Saati',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  controller: _decisionDateController,
                  label: 'Kurul Toplantı / Karar Tarihi',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Şube ve Asıl Öğrenci Seçimi
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _compactDropdown(
                  label: 'Şube Seçimi',
                  value: ctx.classes.any((c) => c.className == _selectedClass)
                      ? _selectedClass
                      : null,
                  items: ctx.classes.map((c) => c.className).toList(),
                  hint: 'Şube',
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() {
                      _selectedClass = val;
                      _selectedStudentLabel = '';
                    });
                    await _loadClassStudents(val, autoPickFirst: true);
                    _onSharedFieldChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _loadingStudents
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: LinearProgressIndicator(),
                      )
                    : _compactDropdown(
                        label: 'Hakkında İşlem Yapılan Öğrenci',
                        value:
                            _classStudents.any(
                              (s) => s.displayLabel == _selectedStudentLabel,
                            )
                            ? _selectedStudentLabel
                            : null,
                        items: _classStudents
                            .map((s) => s.displayLabel)
                            .toList(),
                        hint: 'Öğrenci seçiniz...',
                        onChanged: (val) {
                          if (val == null) return;
                          final found = _classStudents
                              .where((s) => s.displayLabel == val)
                              .toList();
                          setState(() {
                            if (found.isNotEmpty) {
                              _applyPrimaryStudent(found.first);
                            } else {
                              _selectedStudentLabel = val;
                            }
                            _syncSharedFieldsToAllSteps();
                            _refreshFocusedBodyController();
                          });
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactTextField(
            controller: _parentNameController,
            label: 'Öğrenci Velisi Adı Soyadı ve Telefonu',
            hint: 'Örn: Mehmet YILMAZ (Babası) — 05xx xxx xx xx',
            onChanged: (_) => _onSharedFieldChanged(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  controller: _victimNameController,
                  label: 'Varsa Mağdur / Şikâyetçi Öğrenci (ÖDDK-07)',
                  hint: 'Ad Soyad (Şube - No)',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  controller: _witnessNameController,
                  label: 'Varsa Görgü Tanığı (ÖDDK-08)',
                  hint: 'Öğrenci veya Personel Adı',
                  onChanged: (_) => _onSharedFieldChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Olay Yeri ve Olay Özeti
          _compactTextField(
            controller: _locationController,
            label: 'Olayın Meydana Geldiği Tam Mahal / Kamera Açısı',
            onChanged: (_) => _onSharedFieldChanged(),
          ),
          const SizedBox(height: 8),
          _compactTextField(
            controller: _incidentSummaryController,
            label:
                'Ortak Olay Konusu ve Kronolojik Özeti (Sevk, İfade & Savunmaya Aktarılır)',
            maxLines: 3,
            onChanged: (_) => _onSharedFieldChanged(),
          ),
          const SizedBox(height: 10),

          // Görevli Öğretmen, Kurul Başkanı, PDR ve Kurul Üyeleri
          Row(
            children: [
              Expanded(
                child: _compactDropdown(
                  label: 'Sınıf Rehber / Sevk Öğretmeni',
                  value: staffNames.contains(_advisorTeacher)
                      ? _advisorTeacher
                      : null,
                  items: staffNames,
                  hint: 'Öğretmen seçiniz',
                  onChanged: (v) {
                    if (v == null) return;
                    _advisorTeacher = v;
                    _onSharedFieldChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactDropdown(
                  label: 'Kurul Başkanı (Md. Yrd.)',
                  value: staffNames.contains(_boardChair) ? _boardChair : null,
                  items: staffNames,
                  hint: 'Kurul başkanı',
                  onChanged: (v) {
                    if (v == null) return;
                    _boardChair = v;
                    _onSharedFieldChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactDropdown(
                  label: 'Okul Rehber Öğretmeni / PDR',
                  value: staffNames.contains(_counselor) ? _counselor : null,
                  items: staffNames,
                  hint: 'PDR uzmanı seçiniz',
                  onChanged: (v) {
                    if (v == null) return;
                    _counselor = v;
                    _onSharedFieldChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: _showBoardMembersPickerDialog,
                  child: InputDecorator(
                    decoration: _fieldDecoration('Kurul Üyesi Öğretmenler'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _boardMembers.isEmpty
                                ? 'Üye seçiniz...'
                                : '${_boardMembers.length} Üye Seçili',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.group_add_rounded,
                          size: 16,
                          color: Color(0xFF475569),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Nihai Karar / Yaptırım
          _compactDropdown(
            label: 'Kurul Nihai Değerlendirme / Yaptırım Kararı (ÖDDK-14 & 15)',
            value: _verdictOptions.contains(_finalVerdict)
                ? _finalVerdict
                : _verdictOptions.first,
            items: _verdictOptions,
            hint: 'Karar seçiniz',
            onChanged: (v) {
              if (v == null) return;
              _finalVerdict = v;
              _onSharedFieldChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeChoice({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF991B1B) : const Color(0xFFE2E8F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 15,
                  color: selected
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.6,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.3, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOL PANEL 2: HAZIR SENARYOLAR VE 16 ADIM SEÇİCİ LİSTESİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStepSelectorCard({required bool isMobile}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.checklist_rtl_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. Dosyaya Eklenecek Adımlar (${_selectedStepIds.length} / 16)',
                      style: GoogleFonts.inter(
                        fontSize: 13.6,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const Text(
                      'Bir adıma dokunarak sağ panelde metnini ve maddelerini özelleştirebilirsiniz.',
                      style: TextStyle(
                        fontSize: 11.1,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Hızlı Paket Senaryoları
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetButton('Tam Paket (16 Adım)', () => _applyPreset(0)),
              _presetButton(
                '1. Aşama: Sözlü Uyarı & EK-9 (01–03)',
                () => _applyPreset(1),
              ),
              _presetButton(
                '2. Aşama: Olay, İfade & Savunma (04–11)',
                () => _applyPreset(2),
              ),
              _presetButton(
                '3. Aşama: Kurul Karar & Tebligat (12–16)',
                () => _applyPreset(3),
              ),
              _presetButton('Doğrudan Disiplin Vakası', () => _applyPreset(4)),
            ],
          ),
          const SizedBox(height: 8),

          // Kapak ve Dizi Pusulası Anahtarı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Switch.adaptive(
                  value: _includeCoverAndIndex,
                  activeTrackColor: const Color(0xFF991B1B),
                  onChanged: (v) => setState(() => _includeCoverAndIndex = v),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _focusedStepId = '__cover__');
                      if (isMobile) _mobileTabController.animateTo(2);
                    },
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Sayfaya Resmi Vaka Kapağı ve Evrak Dizi Pusulası Ekle',
                          style: TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Dosya numarası, öğrenci künyesi ve seçili tüm evrakların sıra numaralı dizi tablosu',
                          style: TextStyle(
                            fontSize: 10.6,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 16 Adım Listesi
          for (final step in _allSteps)
            Builder(
              builder: (_) {
                final checked = _selectedStepIds.contains(step.id);
                final focused = _focusedStepId == step.id;
                final isEdited = _manualStepBodies.containsKey(step.id);

                return Container(
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    color: focused
                        ? const Color(0xFFEEF2FF)
                        : (checked ? Colors.white : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: focused
                          ? const Color(0xFF3730A3)
                          : (checked
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFFE2E8F0)),
                      width: focused ? 1.4 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _focusedStepId = step.id;
                        _refreshFocusedBodyController();
                      });
                      if (isMobile) _mobileTabController.animateTo(2);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                if (checked) {
                                  _selectedStepIds.remove(step.id);
                                } else {
                                  _selectedStepIds.add(step.id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                checked
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 20,
                                color: checked
                                    ? const Color(0xFF991B1B)
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: checked
                                  ? const Color(
                                      0xFF991B1B,
                                    ).withValues(alpha: 0.12)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              step.code,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: checked
                                    ? const Color(0xFF991B1B)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.8,
                                fontWeight: checked
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: checked
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF64748B),
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (isEdited)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Özel',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_note_rounded,
                            size: 17,
                            color: focused
                                ? const Color(0xFF3730A3)
                                : const Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _presetButton(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10.8,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAĞ PANEL: DİZİ PUSULASI ÖZETİ VEYA SEÇİLEN ADIM İNCE AYAR & METİN ÖNİZLEME
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildRightPreviewPane() {
    final activeStepList = _allSteps
        .where((s) => s.id == _focusedStepId)
        .toList();
    final activeStep = activeStepList.isNotEmpty ? activeStepList.first : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        // Üst Hızlı Adım Geçiş Şeridi
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _stepPill(
                label: 'Kapak & Dizi Pusulası',
                selected: _focusedStepId == '__cover__',
                included: _includeCoverAndIndex,
                onTap: () => setState(() => _focusedStepId = '__cover__'),
              ),
              for (final step in _allSteps)
                _stepPill(
                  label: step.code,
                  selected: _focusedStepId == step.id,
                  included: _selectedStepIds.contains(step.id),
                  onTap: () {
                    setState(() {
                      _focusedStepId = step.id;
                      _refreshFocusedBodyController();
                    });
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (activeStep == null)
          _buildCoverPreviewCard()
        else
          _buildSingleStepEditorCard(activeStep),
      ],
    );
  }

  Widget _stepPill({
    required String label,
    required bool selected,
    required bool included,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1E3A8A)
                : (included ? Colors.white : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1E3A8A)
                  : (included
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (included)
                Icon(
                  Icons.check_circle_rounded,
                  size: 12,
                  color: selected ? Colors.white : const Color(0xFF059669),
                ),
              if (included) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.2,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? Colors.white
                      : (included
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPreviewCard() {
    final items = _buildSelectedBundleItems();
    final effCtx = _effectiveContext();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 3.5,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Text(
                'HİZMETE ÖZEL / GİZLİ — BİRLEŞİK SORUŞTURMA VAKA DOSYASI ÖNİZLEMESİ',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'T.C.\n${effCtx.city.toUpperCase()} VALİLİĞİ / ${effCtx.district.toUpperCase()} KAYMAKAMLIĞI\n${effCtx.schoolName.toUpperCase()}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 18),
          _compactTextField(
            controller: _dossierTitleController,
            label: 'Dosya Kapak Başlığı (Düzenlenebilir)',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaPreviewRow('Dosya Numarası', _fileNoController.text),
                _metaPreviewRow('Kurul Adı', _boardDisplayName),
                _metaPreviewRow(
                  'Öğrenci / Şube',
                  '$_selectedStudentLabel ($_selectedClass)',
                ),
                _metaPreviewRow('Veli Bilgisi', _parentNameController.text),
                _metaPreviewRow(
                  'Olay Zamanı & Yeri',
                  '${_incidentDateController.text} — ${_locationController.text}',
                ),
                _metaPreviewRow('Nihai Karar', _finalVerdict),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'TEK PDF İÇİNDE YER ALACAK KRONOLOJİK EVRAK DİZİ PUSULASI (${items.length} EVRAK)',
            style: const TextStyle(
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Henüz seçili bir ÖDDK adımı yok. Sol panelden dosyaya eklenecek adımları işaretleyiniz.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            for (int i = 0; i < items.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _focusedStepId = items[i].template.id;
                    _refreshFocusedBodyController();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: i.isEven ? const Color(0xFFF8FAFC) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${i + 1}.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          items[i].template.code,
                          style: const TextStyle(
                            fontSize: 10.2,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          items[i].documentTitle,
                          style: const TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'İncele / Düzenle →',
                        style: TextStyle(
                          fontSize: 10.8,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _metaPreviewRow(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              '$k:',
              style: const TextStyle(
                fontSize: 11.3,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleStepEditorCard(OfficialDocTemplate step) {
    final included = _selectedStepIds.contains(step.id);
    final a = _stepAnswers.putIfAbsent(step.id, () => <String, dynamic>{});
    final effCtx = _effectiveContext();
    final metaRows = step.buildMetaRows?.call(a, effCtx) ?? const [];
    final signers = _signersForStep(step);
    final hasManualBody = _manualStepBodies.containsKey(step.id);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Evrak Başlığı ve Tekil Aksiyonlar
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF991B1B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      step.code,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: included,
                    label: Text(
                      included
                          ? 'Birleşik PDF\'e Dahil'
                          : 'Dosyaya Dahil Değil',
                      style: TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                        color: included
                            ? const Color(0xFF059669)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    onSelected: (v) {
                      setState(() {
                        v
                            ? _selectedStepIds.add(step.id)
                            : _selectedStepIds.remove(step.id);
                      });
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _showStepQuestions = !_showStepQuestions,
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    icon: Icon(
                      _showStepQuestions
                          ? Icons.expand_less_rounded
                          : Icons.tune_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _showStepQuestions
                          ? 'Maddeleri Gizle'
                          : 'Bu Adımın Maddelerini Özelleştir',
                      style: const TextStyle(
                        fontSize: 11.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isGeneratingPdf
                        ? null
                        : () => _exportSingleStepPdf(step),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF1E3A8A),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: Text(
                      'Sadece ${step.code} PDF',
                      style: const TextStyle(
                        fontSize: 11.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            style: GoogleFonts.inter(
              fontSize: 14.2,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          if (step.legalBasis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Mevzuat Dayanağı: ${step.legalBasis}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),

          // Adıma Özel Sorular & Çoklu Madde (multiCheck) Seçici
          if (_showStepQuestions) ...[
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in step.questions) ...[
                    _buildStepQuestionEditor(step, q, a),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],

          const Divider(height: 20),

          // Künye Tablosu Önizleme
          if (metaRows.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  for (final r in metaRows) _metaPreviewRow(r.key, r.value),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Düzenlenebilir Resmi Evrak Metni
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Resmi Evrak Metni (Doğrudan Düzenlenebilir)',
                style: TextStyle(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
              if (hasManualBody)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _manualStepBodies.remove(step.id);
                      _refreshFocusedBodyController();
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text(
                    'Otomatik Şablona Sıfırla',
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _activeBodyController,
            maxLines: 15,
            style: const TextStyle(
              fontSize: 12.4,
              height: 1.45,
              color: Color(0xFF0F172A),
            ),
            onChanged: (val) {
              _manualStepBodies[step.id] = val;
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFFCFDFF),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // İmza Bloğu Özeti
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final s in signers)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: s.isApproval
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: s.isApproval
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 11.6,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepQuestionEditor(
    OfficialDocTemplate step,
    DocQuestionField q,
    Map<String, dynamic> a,
  ) {
    final searchKey = '${step.id}__${q.key}';

    if (q.type == DocFieldType.multiCheck) {
      final selected = (a[q.key] is List)
          ? List<String>.from((a[q.key] as List).map((e) => e.toString()))
          : <String>[];
      final customList = _customMultiCheckItems[searchKey] ?? const <String>[];
      final allItems = <String>{
        ...q.options,
        ...customList,
        ...selected,
      }.toList();
      final query = _normTr(_multiCheckSearch[searchKey] ?? '');
      final filtered = query.isEmpty
          ? allItems
          : allItems.where((it) => _normTr(it).contains(query)).toList();
      final allSelected =
          allItems.isNotEmpty && selected.length >= allItems.length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.label,
                  style: const TextStyle(
                    fontSize: 11.6,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    a[q.key] = allSelected
                        ? <String>[]
                        : List<String>.from(allItems);
                    _manualStepBodies.remove(step.id);
                    _refreshFocusedBodyController();
                  });
                },
                child: Text(
                  allSelected ? 'Tümünü Kaldır' : 'Tümünü Seç',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showAddClauseDialog(q.label, (txt) {
                  setState(() {
                    final list = List<String>.from(
                      _customMultiCheckItems[searchKey] ?? const <String>[],
                    )..add(txt);
                    _customMultiCheckItems[searchKey] = list;
                    final next = List<String>.from(selected)..add(txt);
                    a[q.key] = next;
                    _manualStepBodies.remove(step.id);
                    _refreshFocusedBodyController();
                  });
                }),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14),
                label: const Text(
                  'Özel Madde',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (allItems.length >= 7) ...[
            TextField(
              onChanged: (v) =>
                  setState(() => _multiCheckSearch[searchKey] = v),
              style: const TextStyle(fontSize: 11.5),
              decoration: _fieldDecoration(
                'Maddeler içinde ara (${allItems.length} madde)...',
              ),
            ),
            const SizedBox(height: 6),
          ],
          for (final item in filtered)
            InkWell(
              onTap: () {
                setState(() {
                  final next = List<String>.from(selected);
                  next.contains(item) ? next.remove(item) : next.add(item);
                  a[q.key] = next;
                  _manualStepBodies.remove(step.id);
                  _refreshFocusedBodyController();
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected.contains(item)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 17,
                      color: selected.contains(item)
                          ? const Color(0xFF1E3A8A)
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 11.6,
                          fontWeight: selected.contains(item)
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    if (q.type == DocFieldType.dropdown && q.options.isNotEmpty) {
      final cur = (a[q.key] ?? '').toString();
      return _compactDropdown(
        label: q.label,
        value: q.options.contains(cur) ? cur : q.options.first,
        items: q.options,
        hint: q.label,
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            a[q.key] = v;
            _manualStepBodies.remove(step.id);
            _refreshFocusedBodyController();
          });
        },
      );
    }

    if (q.type == DocFieldType.text ||
        q.type == DocFieldType.multiline ||
        q.type == DocFieldType.date ||
        q.type == DocFieldType.time) {
      final curVal = (a[q.key] ?? '').toString();
      return TextFormField(
        key: ValueKey('${step.id}_${q.key}_$curVal'.hashCode),
        initialValue: curVal,
        maxLines: q.type == DocFieldType.multiline ? 3 : 1,
        style: const TextStyle(fontSize: 12),
        decoration: _fieldDecoration(q.label, hint: q.hint),
        onChanged: (v) {
          a[q.key] = v;
          _manualStepBodies.remove(step.id);
          _refreshFocusedBodyController();
        },
      );
    }

    return const SizedBox.shrink();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YARDIMCI DİYALOG VE FORM BİLEŞENLERİ
  // ═══════════════════════════════════════════════════════════════════════════
  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
      hintStyle: const TextStyle(fontSize: 11.3, color: Color(0xFF94A3B8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  Widget _compactTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 12.2, color: Color(0xFF0F172A)),
      onChanged: onChanged,
      decoration: _fieldDecoration(label, hint: hint),
    );
  }

  Widget _compactDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    final uniqueItems = items.toSet().toList();
    final safeVal = (value != null && uniqueItems.contains(value))
        ? value
        : null;
    return DropdownButtonFormField<String>(
      key: ValueKey('${label}_${safeVal}_${uniqueItems.length}'),
      initialValue: safeVal,
      isExpanded: true,
      decoration: _fieldDecoration(label),
      hint: Text(
        hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
      ),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F172A),
      ),
      items: uniqueItems
          .map(
            (e) => DropdownMenuItem<String>(
              value: e,
              child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Future<void> _showBoardMembersPickerDialog() async {
    final ctx = _ctx;
    if (ctx == null) return;
    final temp = Set<String>.from(_boardMembers);
    String search = '';

    await showDialog<void>(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (dCtx, setModal) {
            final filtered = ctx.allStaff.where((s) {
              if (search.trim().isEmpty) return true;
              return _normTr(s.displayLabel).contains(_normTr(search));
            }).toList();

            return AlertDialog(
              title: const Text(
                'Kurul Üyesi Öğretmenleri Seçin',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 440,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      onChanged: (v) => setModal(() => search = v),
                      decoration: _fieldDecoration(
                        'Öğretmen veya branş ara...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, idx) {
                          final st = filtered[idx];
                          final checked = temp.contains(st.fullName);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            title: Text(
                              st.fullName,
                              style: const TextStyle(
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              st.groupLabel,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onChanged: (v) {
                              setModal(() {
                                v == true
                                    ? temp.add(st.fullName)
                                    : temp.remove(st.fullName);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    _boardMembers = temp.toList();
                    _onSharedFieldChanged();
                    Navigator.pop(dCtx);
                  },
                  child: Text('Uygula (${temp.length} Üye)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddClauseDialog(
    String title,
    ValueChanged<String> onAdded,
  ) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(
          '$title — Özel Madde Ekle',
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: _fieldDecoration(
            'Eklenecek resmi tutanak maddesini yazınız',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) onAdded(v);
              Navigator.pop(dCtx);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }
}
