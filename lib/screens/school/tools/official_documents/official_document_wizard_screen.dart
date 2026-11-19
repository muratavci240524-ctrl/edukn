import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/official_document_model.dart';
import '../../../../services/official_document_context_service.dart';
import '../../../../services/official_document_pdf_service.dart';
import '../../../../services/web_share/web_file_share.dart';
import '../../../../widgets/edukn_app_bar.dart';

class OfficialDocumentWizardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final OfficialDocTemplate template;
  final OfficialDocCategory category;
  final SavedOfficialDocument? existingDocument;
  final List<String>? allowedClassIds;

  const OfficialDocumentWizardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.template,
    required this.category,
    this.existingDocument,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<OfficialDocumentWizardScreen> createState() =>
      _OfficialDocumentWizardScreenState();
}

class _OfficialDocumentWizardScreenState
    extends State<OfficialDocumentWizardScreen>
    with SingleTickerProviderStateMixin {
  final OfficialDocumentContextService _contextService =
      OfficialDocumentContextService();

  SchoolDocContext? _ctx;
  bool _isLoading = true;
  bool _isGeneratingPdf = false;
  bool _isSaving = false;
  String _savedDocId = '';

  late TabController _mobileTabController;
  late DocHeaderStyle _headerStyle;

  final TextEditingController _docTitleController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _authorityNameController =
      TextEditingController();
  final TextEditingController _authorityTitleController =
      TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _textControllers = {};

  List<DocStudentItem> _loadedStudents = [];
  bool _loadingStudents = false;
  bool _isBodyManuallyEdited = false;
  bool _areSignersManuallyEdited = false;
  List<DocSigner> _signers = [];

  // İmza Sirküsü / Öğretmen Listesi Özelleştirme Durumu
  final List<DocStaffItem> _customSigStaff = [];
  final Map<String, String> _sigStaffBranchOverrides = {};
  final Set<String> _selectedSigStaffIds = {};
  final Set<String> _customSigBranches = {};
  int _sigFilterMode = 0; // 0: Zümre / Branşa Göre, 1: Kişiye Göre
  String _sigBranchSearch = '';
  String _sigStaffSearch = '';

  // Çoklu Madde (multiCheck) Arama ve Özel Madde Havuzu
  final Map<String, String> _multiCheckSearch = {};
  final Map<String, List<String>> _customMultiCheckItems = {};

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

  static int _turkishCompare(String a, String b) {
    const alphabet = ' 0123456789abcçdefgğhıijklmnoöprsştuüvyz';
    final aL = _normTr(a);
    final bL = _normTr(b);
    final minLen = aL.length < bL.length ? aL.length : bL.length;
    for (int i = 0; i < minLen; i++) {
      final ca = aL[i];
      final cb = bL[i];
      if (ca != cb) {
        final ia = alphabet.indexOf(ca);
        final ib = alphabet.indexOf(cb);
        if (ia != -1 && ib != -1) return ia.compareTo(ib);
        return ca.compareTo(cb);
      }
    }
    return aL.length.compareTo(bL.length);
  }

  String _sigKey(DocStaffItem s) =>
      s.id.isNotEmpty ? s.id : 'staff_${s.fullName}_${s.branch}';

  List<DocStaffItem> _allSignaturePoolStaff() {
    final ctx = _ctx;
    if (ctx == null) return const [];
    final list = <DocStaffItem>[
      for (final s in ctx.allStaff)
        _sigStaffBranchOverrides.containsKey(_sigKey(s))
            ? s.copyWith(branch: _sigStaffBranchOverrides[_sigKey(s)])
            : s,
      ..._customSigStaff,
    ];
    list.sort((a, b) => _turkishCompare(a.fullName, b.fullName));
    return list;
  }

  bool get _isKurulChairTemplate =>
      widget.template.id == 'ogretmenler_kurulu_tutanagi' ||
      widget.template.id == 'sok_toplanti_tutanagi' ||
      widget.template.id == 'oddk_12_kurul_toplanti_cagrisi_ve_teblig' ||
      widget.template.id == 'oddk_14_kurul_gerekceli_karar_tutanagi' ||
      widget.template.id == 'oddk_16_izleme_ceza_kaldirma_ve_dizi_pusulasi';

  bool get _isBoardOrMeetingTemplate =>
      _isKurulChairTemplate ||
      widget.category.id == 'idari_kurul_komisyon' ||
      widget.category.id == 'oddk_disiplin_surec_paketi' ||
      widget.template.layoutKind == DocLayoutKind.meetingMinutes;

  String _defaultAuthorityTitle() {
    if (widget.template.id == 'ogretmenler_kurulu_tutanagi') {
      return 'Kurul Başkanı / Okul Müdürü';
    }
    if (widget.template.id == 'sok_toplanti_tutanagi') {
      return 'ŞÖK Başkanı';
    }
    final stNorm = _normTr(widget.schoolTypeName);
    if (widget.category.id == 'ozel_ogretim_kurs_ozel' ||
        stNorm.contains('kurs') ||
        stNorm.contains('etut')) {
      return 'Kurum Müdürü';
    }
    return 'Okul Müdürü';
  }

  String get _authorityNameLabel {
    if (_isKurulChairTemplate) return 'Kurul Başkanı Adı Soyadı';
    if (_isBoardOrMeetingTemplate) return 'Kurul / Onay Yetkilisi Adı Soyadı';
    return 'Yetkili / Müdür Adı Soyadı';
  }

  String get _authorityTitleLabel {
    if (_isKurulChairTemplate) return 'Kurul Başkanı Unvanı';
    if (_isBoardOrMeetingTemplate) return 'Başkan / Yetkili Unvanı';
    return 'Yetkili Unvanı (Müdür, Md. V., Md. Yrd. vb.)';
  }

  SchoolDocContext _effectiveContext() {
    final base = _ctx!;
    return base.copyWith(
      schoolName: _schoolNameController.text.trim().isNotEmpty
          ? _schoolNameController.text.trim()
          : base.schoolName,
      city: _provinceController.text.trim(),
      district: _districtController.text.trim(),
      principalName: _authorityNameController.text.trim().isNotEmpty
          ? _authorityNameController.text.trim()
          : base.principalName,
      principalTitle: _authorityTitleController.text.trim().isNotEmpty
          ? _authorityTitleController.text.trim()
          : 'Okul Müdürü',
    );
  }

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 2, vsync: this);
    _headerStyle =
        widget.existingDocument?.headerStyle ??
        widget.template.defaultHeaderStyle;
    _savedDocId = widget.existingDocument?.id ?? '';
    _docTitleController.text =
        widget.existingDocument?.title ?? widget.template.title;
    _initBootstrap();
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
    _docTitleController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    _schoolNameController.dispose();
    _authorityNameController.dispose();
    _authorityTitleController.dispose();
    _bodyController.dispose();
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initBootstrap() async {
    final ctx = await _contextService.loadContext(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      allowedClassIds: widget.allowedClassIds,
    );

    final savedAns = widget.existingDocument?.answers;
    _provinceController.text = (savedAns?['__customProvince'] ?? ctx.city)
        .toString();
    _districtController.text = (savedAns?['__customDistrict'] ?? ctx.district)
        .toString();
    _schoolNameController.text =
        (savedAns?['__customSchoolName'] ?? ctx.schoolName).toString();
    _authorityNameController.text =
        (savedAns?['__customAuthorityName'] ?? ctx.principalName).toString();
    _authorityTitleController.text =
        (savedAns?['__customAuthorityTitle'] ?? _defaultAuthorityTitle())
            .toString();

    // Varsayılan cevapları doldur
    for (final q in widget.template.questions) {
      if (widget.existingDocument != null &&
          widget.existingDocument!.answers.containsKey(q.key)) {
        final raw = widget.existingDocument!.answers[q.key];
        _answers[q.key] = raw is List
            ? List<String>.from(raw.map((e) => e.toString()))
            : raw;
      } else if (q.defaultValue != null) {
        _answers[q.key] = q.defaultValue is List
            ? List<String>.from(
                (q.defaultValue as List).map((e) => e.toString()),
              )
            : q.defaultValue;
      } else {
        // Akıllı başlangıç değerleri
        if (q.key == 'chairPerson') {
          _answers[q.key] = _authorityNameController.text;
        } else if (q.type == DocFieldType.branchSelect &&
            (ctx.currentUser?.branch.isNotEmpty ?? false)) {
          _answers[q.key] = ctx.currentUser!.branch;
        } else if (q.type == DocFieldType.classSelect &&
            ctx.classes.isNotEmpty) {
          _answers[q.key] = ctx.classes.first.className;
        } else if (q.type == DocFieldType.multiClassSelect &&
            ctx.classes.isNotEmpty) {
          _answers[q.key] = <String>[ctx.classes.first.className];
        } else if (q.type == DocFieldType.staffSelect &&
            ctx.currentUser != null) {
          _answers[q.key] = ctx.currentUser!.fullName;
        } else if (q.type == DocFieldType.multiCheck ||
            q.type == DocFieldType.multiStaffSelect ||
            q.type == DocFieldType.multiStudentSelect) {
          _answers[q.key] = <String>[];
        } else {
          _answers[q.key] = '';
        }
      }

      if (q.type == DocFieldType.text ||
          q.type == DocFieldType.multiline ||
          q.type == DocFieldType.date ||
          q.type == DocFieldType.time) {
        _textControllers[q.key] = TextEditingController(
          text: (_answers[q.key] ?? '').toString(),
        );
      }
    }

    // Zümre şablonunda branşa ait öğretmenleri başlangıçta otomatik seç
    if (widget.existingDocument == null &&
        widget.template.id == 'brans_zumre_tutanagi') {
      final selBranch = (_answers['branch'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (selBranch.isNotEmpty) {
        final matching = ctx.allStaff
            .where(
              (s) =>
                  s.branch.toLowerCase().contains(selBranch) ||
                  selBranch.contains(s.branch.toLowerCase()),
            )
            .where((s) => s.branch.isNotEmpty)
            .map((s) => s.fullName)
            .toList();
        if (matching.isNotEmpty) {
          _answers['members'] = matching;
        }
      }
    }

    // ŞÖK tutanaklarında seçili şubenin derse giren TÜM öğretmenlerini (kurlu dersler dahil) otomatik seç
    if (widget.existingDocument == null &&
        widget.template.id == 'sok_toplanti_tutanagi') {
      final cls = (_answers['targetClass'] ?? '').toString().trim();
      _answers['sokTeachers'] = List<String>.from(
        ctx.classTeachersByClass[cls] ?? const [],
      );
    }
    if (widget.existingDocument == null &&
        widget.template.id == 'ilkogretim_sinif_gecme_tekrar_tutanagi') {
      final cls = (_answers['targetClass'] ?? '').toString().trim();
      final fullList = ctx.classTeachersByClass[cls] ?? const [];
      if (fullList.isNotEmpty) {
        _answers['teachers'] = fullList
            .map((t) => t.split('(').first.trim())
            .where((t) => t.isNotEmpty)
            .toList();
      }
    }

    // İmza sirküsü öğretmen/branş seçimlerini başlat (varsayılan: tümü seçili)
    _customSigStaff.clear();
    _sigStaffBranchOverrides.clear();
    _customSigBranches.clear();
    _selectedSigStaffIds.clear();

    if (savedAns != null) {
      if (savedAns['__customSigStaff'] is List) {
        for (final raw in (savedAns['__customSigStaff'] as List)) {
          if (raw is Map) {
            _customSigStaff.add(
              DocStaffItem.fromMap(Map<String, dynamic>.from(raw)),
            );
          }
        }
      }
      if (savedAns['__sigStaffBranchOverrides'] is Map) {
        (savedAns['__sigStaffBranchOverrides'] as Map).forEach((k, v) {
          _sigStaffBranchOverrides[k.toString()] = v.toString();
        });
      }
      if (savedAns['__customSigBranches'] is List) {
        _customSigBranches.addAll(
          (savedAns['__customSigBranches'] as List).map((e) => e.toString()),
        );
      }
    }

    if (savedAns != null && savedAns['__selectedSigStaffIds'] is List) {
      final validPoolIds = {
        for (final s in ctx.allStaff) _sigKey(s),
        for (final s in _customSigStaff) _sigKey(s),
      };
      _selectedSigStaffIds.addAll(
        (savedAns['__selectedSigStaffIds'] as List)
            .map((e) => e.toString())
            .where((id) => validPoolIds.contains(id)),
      );
    } else {
      for (final s in ctx.allStaff) {
        _selectedSigStaffIds.add(_sigKey(s));
      }
      for (final s in _customSigStaff) {
        _selectedSigStaffIds.add(_sigKey(s));
      }
    }

    if (!mounted) return;
    setState(() {
      _ctx = ctx;
      _isLoading = false;
    });

    await _reloadStudentsForSelectedClasses();

    if (widget.existingDocument != null &&
        widget.existingDocument!.composedBody.trim().isNotEmpty) {
      _bodyController.text = widget.existingDocument!.composedBody;
      _areSignersManuallyEdited =
          widget.existingDocument!.answers['__signersEdited'] == true;
      final isSokDoc =
          widget.template.id == 'sok_toplanti_tutanagi' ||
          widget.template.id == 'ilkogretim_sinif_gecme_tekrar_tutanagi';
      if (!_areSignersManuallyEdited &&
          isSokDoc &&
          widget.existingDocument!.signers.length > 2) {
        _signers =
            widget.template.buildSigners?.call(_answers, _effectiveContext()) ??
            [];
      } else {
        _signers = List<DocSigner>.from(widget.existingDocument!.signers);
      }
      _isBodyManuallyEdited = true;
    } else {
      _recomposeFromTemplate(force: true);
    }
  }

  Future<void> _reloadStudentsForSelectedClasses() async {
    final ctx = _ctx;
    if (ctx == null) return;

    final Set<String> selectedClassNames = {};
    for (final q in widget.template.questions) {
      if (q.type == DocFieldType.classSelect) {
        final val = (_answers[q.key] ?? '').toString().trim();
        if (val.isNotEmpty) selectedClassNames.add(val);
      } else if (q.type == DocFieldType.multiClassSelect) {
        final list = _answers[q.key];
        if (list is List) {
          for (final item in list) {
            final s = item.toString().trim();
            if (s.isNotEmpty) selectedClassNames.add(s);
          }
        }
      }
    }

    if (selectedClassNames.isEmpty) {
      if (mounted) setState(() => _loadedStudents = []);
      return;
    }

    final targetClasses = ctx.classes
        .where((c) => selectedClassNames.contains(c.className))
        .toList();
    if (targetClasses.isEmpty) return;

    setState(() => _loadingStudents = true);
    final students = await _contextService.loadStudentsForClasses(
      institutionId: widget.institutionId,
      targetClasses: targetClasses,
    );
    if (!mounted) return;
    setState(() {
      _loadedStudents = students;
      _loadingStudents = false;
    });
  }

  void _recomposeFromTemplate({bool force = false}) {
    if (_ctx == null) return;
    final effCtx = _effectiveContext();
    if (!force && _isBodyManuallyEdited) {
      setState(() {
        if (!_areSignersManuallyEdited) {
          _signers = widget.template.buildSigners?.call(_answers, effCtx) ?? [];
        }
      });
      return;
    }
    final text = widget.template.composeBody(_answers, effCtx);
    final signers = widget.template.buildSigners?.call(_answers, effCtx) ?? [];
    setState(() {
      _bodyController.text = text;
      if (!_areSignersManuallyEdited || force) {
        _signers = signers;
      }
      if (force) {
        _isBodyManuallyEdited = false;
        _areSignersManuallyEdited = false;
      }
    });
  }

  void _updateAnswer(String key, dynamic value, {bool reloadStudents = false}) {
    setState(() {
      _answers[key] = value;
      if (key == 'chairPerson' && value != null) {
        _authorityNameController.text = value.toString();
      }
    });

    // Branş değiştiğinde Zümre öğretmenlerini otomatik öner
    if (key == 'branch' &&
        widget.template.id == 'brans_zumre_tutanagi' &&
        _ctx != null) {
      final sel = value.toString().toLowerCase().trim();
      final matched = _ctx!.allStaff
          .where(
            (s) =>
                s.branch.isNotEmpty &&
                (s.branch.toLowerCase().contains(sel) ||
                    sel.contains(s.branch.toLowerCase())),
          )
          .map((s) => s.fullName)
          .toList();
      if (matched.isNotEmpty) {
        _answers['members'] = matched;
      }
    }

    // Şube değiştiğinde ŞÖK tutanağındaki tüm ders öğretmenlerini otomatik yenile
    if (key == 'targetClass' && _ctx != null) {
      final cls = value?.toString().trim() ?? '';
      if (widget.template.id == 'sok_toplanti_tutanagi') {
        _answers['sokTeachers'] = List<String>.from(
          _ctx!.classTeachersByClass[cls] ?? const [],
        );
        _areSignersManuallyEdited = false;
      } else if (widget.template.id ==
          'ilkogretim_sinif_gecme_tekrar_tutanagi') {
        final fullList = _ctx!.classTeachersByClass[cls] ?? const [];
        _answers['teachers'] = fullList
            .map((t) => t.split('(').first.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        _areSignersManuallyEdited = false;
      }
    }

    // ŞÖK öğretmen listesi işaretlenip/kaldırıldığında Alt İmza Bloğunu da senkron tut
    if (key == 'sokTeachers' && widget.template.id == 'sok_toplanti_tutanagi') {
      _areSignersManuallyEdited = false;
    }

    // Öğrenci seçildiğinde veli adı alanı varsa otomatik doldur
    if (key == 'student' && _answers.containsKey('parentName')) {
      final stName = value.toString();
      final match = _loadedStudents.where(
        (s) => s.fullName == stName || s.displayLabel == stName,
      );
      if (match.isNotEmpty && match.first.parentName.isNotEmpty) {
        _answers['parentName'] = match.first.parentName;
        _textControllers['parentName']?.text = match.first.parentName;
      }
    }

    if (reloadStudents) {
      _reloadStudentsForSelectedClasses();
    }
    _recomposeFromTemplate();
  }

  List<DocStaffItem> _resolveSignatureStaff() {
    if (_ctx == null) return const [];

    // ŞÖK Toplantı Tutanağı: seçili şubenin işaretli ders & rehber öğretmenlerini İmza Sirküsü Tablosuna aktar
    if (widget.template.id == 'sok_toplanti_tutanagi') {
      final cls = (_answers['targetClass'] ?? '').toString().trim();
      final List<String> rawList = _answers.containsKey('sokTeachers')
          ? (_answers['sokTeachers'] is List
                ? (_answers['sokTeachers'] as List)
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList()
                : <String>[])
          : (_ctx!.classTeachersByClass[cls] ?? const <String>[]);

      return List.generate(rawList.length, (i) {
        final entry = rawList[i];
        final pIdx = entry.indexOf('(');
        final lIdx = entry.lastIndexOf(')');
        final name = pIdx > 0 ? entry.substring(0, pIdx).trim() : entry.trim();
        final branch = (pIdx > 0 && lIdx > pIdx)
            ? entry.substring(pIdx + 1, lIdx).trim()
            : 'Ders Öğretmeni';
        final cleanBranch = branch.isNotEmpty ? branch : 'Ders Öğretmeni';
        return DocStaffItem(
          id: 'sok_sig_$i',
          fullName: name,
          role: cleanBranch,
          branch: cleanBranch,
        );
      });
    }

    // İlköğretim Sınıf Geçme / Tekrar ŞÖK Tutanağı: seçili öğretmenleri branşlarıyla İmza Sirküsü Tablosuna aktar
    if (widget.template.id == 'ilkogretim_sinif_gecme_tekrar_tutanagi') {
      final cls = (_answers['targetClass'] ?? '').toString().trim();
      final classLabeled = _ctx!.classTeachersByClass[cls] ?? const <String>[];
      final Map<String, String> nameToBranch = {};
      for (final entry in classLabeled) {
        final pIdx = entry.indexOf('(');
        final lIdx = entry.lastIndexOf(')');
        final n = (pIdx > 0 ? entry.substring(0, pIdx) : entry).trim();
        final b = (pIdx > 0 && lIdx > pIdx)
            ? entry.substring(pIdx + 1, lIdx).trim()
            : '';
        if (n.isNotEmpty && b.isNotEmpty) {
          nameToBranch[_normTr(n).replaceAll('ı', 'i')] = b;
        }
      }
      for (final s in _ctx!.allStaff) {
        final key = _normTr(s.fullName).replaceAll('ı', 'i');
        if (s.groupLabel.isNotEmpty) {
          nameToBranch.putIfAbsent(key, () => s.groupLabel);
        }
      }

      final List<String> selectedNames = _answers['teachers'] is List
          ? (_answers['teachers'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : <String>[];
      final effectiveList = selectedNames.isNotEmpty
          ? selectedNames
          : classLabeled;

      return List.generate(effectiveList.length, (i) {
        final raw = effectiveList[i];
        final pIdx = raw.indexOf('(');
        final lIdx = raw.lastIndexOf(')');
        final name = (pIdx > 0 ? raw.substring(0, pIdx) : raw).trim();
        final inlineBranch = (pIdx > 0 && lIdx > pIdx)
            ? raw.substring(pIdx + 1, lIdx).trim()
            : '';
        final resolvedBranch = inlineBranch.isNotEmpty
            ? inlineBranch
            : (nameToBranch[_normTr(name).replaceAll('ı', 'i')] ??
                  'Kurul Üyesi Öğretmen');
        return DocStaffItem(
          id: 'ilkogretim_sok_sig_$i',
          fullName: name,
          role: resolvedBranch,
          branch: resolvedBranch,
        );
      });
    }

    final pool = _allSignaturePoolStaff();
    return pool
        .where((s) => _selectedSigStaffIds.contains(_sigKey(s)))
        .toList();
  }

  Future<String?> _persistDocument({bool showFeedback = false}) async {
    final ctx = _ctx;
    if (ctx == null) return null;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final persistedAnswers = <String, dynamic>{
        ..._answers,
        '__customProvince': _provinceController.text.trim(),
        '__customDistrict': _districtController.text.trim(),
        '__customSchoolName': _schoolNameController.text.trim(),
        '__customAuthorityName': _authorityNameController.text.trim(),
        '__customAuthorityTitle': _authorityTitleController.text.trim(),
        '__signersEdited': _areSignersManuallyEdited,
        '__customSigStaff': _customSigStaff.map((e) => e.toMap()).toList(),
        '__sigStaffBranchOverrides': _sigStaffBranchOverrides,
        '__customSigBranches': _customSigBranches.toList(),
        '__selectedSigStaffIds': _selectedSigStaffIds.toList(),
      };
      final saved = SavedOfficialDocument(
        id: _savedDocId,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        templateId: widget.template.id,
        categoryId: widget.category.id,
        categoryTitle: widget.category.title,
        title: _docTitleController.text.trim().isNotEmpty
            ? _docTitleController.text.trim()
            : widget.template.title,
        documentSubject: widget.template.subtitle,
        headerStyle: _headerStyle,
        answers: persistedAnswers,
        composedBody: _bodyController.text,
        signers: _signers,
        createdAt: widget.existingDocument?.createdAt ?? DateTime.now(),
        createdBy: user?.uid ?? 'anon',
        creatorName: ctx.currentUser?.fullName ?? 'Yönetici',
        isPassive: widget.existingDocument?.isPassive ?? false,
      );
      final id = await _contextService.saveDocument(saved);
      _savedDocId = id;
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Evrak başarıyla kaydedildi. Hazırlanan Evraklar sekmesinden ulaşabilirsiniz.',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
      return id;
    } catch (e) {
      debugPrint('[OfficialDocumentWizard] Kayıt hatası: $e');
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

  String _trUpper(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  Future<void> _generatePdfAction({required bool downloadOnly}) async {
    if (_ctx == null) return;
    final effCtx = _effectiveContext();
    setState(() => _isGeneratingPdf = true);
    Uint8List? pdfBytes;
    try {
      pdfBytes = await OfficialDocumentPdfService.generate(
        template: widget.template,
        ctx: effCtx,
        headerStyle: _headerStyle,
        customProvince: _provinceController.text,
        customDistrict: _districtController.text,
        customSchoolName: _schoolNameController.text,
        documentTitle: _docTitleController.text.trim().isNotEmpty
            ? _docTitleController.text.trim()
            : widget.template.title,
        answers: _answers,
        composedBody: _bodyController.text,
        signers: _signers,
        students: _loadedStudents,
        signatureStaff: _resolveSignatureStaff(),
      );
      // PDF üretimini bekletmeden arka planda otomatik arşive kaydet
      unawaited(_persistDocument(showFeedback: false));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF oluşturulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }

    if (pdfBytes != null) {
      final rawTitle = _docTitleController.text.trim().isNotEmpty
          ? _docTitleController.text.trim()
          : widget.template.title;
      final fileName = sanitizeFileName('${rawTitle}.pdf');
      try {
        if (downloadOnly) {
          await downloadFileUniversal(bytes: pdfBytes, fileName: fileName);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$fileName indirildi ve arşive kaydedildi.'),
                backgroundColor: const Color(0xFF059669),
              ),
            );
          }
        } else {
          await printFileUniversal(bytes: pdfBytes, fileName: fileName);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF açılamadı: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: EduknAppBar(
        title: widget.template.title,
        subtitle: widget.category.title,
        actions: [
          if (!_isLoading)
            IconButton(
              tooltip: 'Arşive Kaydet',
              onPressed: _isSaving
                  ? null
                  : () => _persistDocument(showFeedback: true),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.bookmark_added_outlined,
                      color: Colors.indigo.shade800,
                    ),
            ),
        ],
        bottom: !isWide
            ? TabBar(
                controller: _mobileTabController,
                labelColor: Colors.indigo.shade900,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo.shade800,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
                tabs: const [
                  Tab(text: '1. SORULAR & BİLGİLER'),
                  Tab(text: '2. RESMİ METİN & İMZA'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWide
          ? Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _buildQuestionsPane()),
                  const SizedBox(width: 20),
                  Expanded(flex: 6, child: _buildPreviewEditorPane()),
                ],
              ),
            )
          : TabBarView(
              controller: _mobileTabController,
              children: [_buildQuestionsPane(), _buildPreviewEditorPane()],
            ),
      bottomNavigationBar: _isLoading
          ? null
          : Container(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 16 : 10,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: width < 580
                    ? Row(
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              final next = _mobileTabController.index == 0
                                  ? 1
                                  : 0;
                              _mobileTabController.animateTo(next);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo.shade900,
                              side: BorderSide(color: Colors.indigo.shade200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              minimumSize: const Size(0, 40),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.visibility_outlined, size: 15),
                                SizedBox(width: 4),
                                Text(
                                  'Önizle',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isGeneratingPdf
                                  ? null
                                  : () =>
                                        _generatePdfAction(downloadOnly: true),
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'PDF İndir',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.8,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo.shade900,
                                side: BorderSide(color: Colors.indigo.shade300),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isGeneratingPdf
                                  ? null
                                  : () =>
                                        _generatePdfAction(downloadOnly: false),
                              icon: _isGeneratingPdf
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.print_rounded, size: 16),
                              label: Text(
                                _isGeneratingPdf ? 'Hazır...' : 'Yazdır / Aç',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade900,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                minimumSize: const Size(0, 40),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          if (_loadingStudents)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (_loadedStudents.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_loadedStudents.length} Öğrenci Hazır',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (!isWide) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                final next = _mobileTabController.index == 0
                                    ? 1
                                    : 0;
                                _mobileTabController.animateTo(next);
                              },
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 16,
                              ),
                              label: const Text(
                                'Önizle',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.indigo.shade900,
                                side: BorderSide(color: Colors.indigo.shade200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          OutlinedButton.icon(
                            onPressed: _isGeneratingPdf
                                ? null
                                : () => _generatePdfAction(downloadOnly: true),
                            icon: const Icon(Icons.download_rounded, size: 17),
                            label: const Text(
                              'PDF İndir',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.2,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo.shade900,
                              side: BorderSide(color: Colors.indigo.shade300),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: _isGeneratingPdf
                                ? null
                                : () => _generatePdfAction(downloadOnly: false),
                            icon: _isGeneratingPdf
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.print_rounded, size: 17),
                            label: Text(
                              _isGeneratingPdf
                                  ? 'Hazırlanıyor...'
                                  : 'Yazdır / PDF Aç',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOL PANEL: ANTET AYARI VE AKILLI SORULAR
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildQuestionsPane() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _buildHeaderConfigCard(),
        const SizedBox(height: 12),
        Container(
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
                      color: widget.category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.quiz_outlined,
                      size: 17,
                      color: widget.category.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Evrak Bilgileri ve Sorular',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Seçimleriniz resmi evrak metnine otomatik işlenir',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),
              if (widget.template.legalBasis.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 16,
                        color: Color(0xFF0369A1),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mevzuat Dayanağı: ${widget.template.legalBasis}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0C4A6E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _buildLabeledField(
                label: 'Evrak Başlığı',
                child: TextField(
                  controller: _docTitleController,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: _compactInputDecoration('Evrak başlığı'),
                ),
              ),
              const SizedBox(height: 12),
              for (final q in widget.template.questions) ...[
                _buildQuestionWidget(q),
                const SizedBox(height: 12),
              ],
              if (widget.template.usesStaffSignatureSelector ||
                  widget.template.id == 'genel_teblig_imza_sirkusu' ||
                  widget.template.id == 'nobet_gorev_teblig_cizelgesi' ||
                  (widget.template.id == 'dinamik_pdf_kontrol_imza_cizelgesi' &&
                      (_answers['listTarget'] ?? '').toString().contains(
                        'Öğretmen',
                      ))) ...[
                _buildSignatureStaffConfigurator(),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        if (widget.template.layoutKind != DocLayoutKind.dynamicChecklist &&
            widget.template.layoutKind != DocLayoutKind.badgeGrid &&
            widget.template.layoutKind != DocLayoutKind.bulkParentSlip) ...[
          const SizedBox(height: 12),
          _buildSignersConfigCard(),
        ],
      ],
    );
  }

  Widget _buildHeaderConfigCard() {
    final ctx = _ctx!;
    const presetTitles = <String>[
      'Okul Müdürü',
      'Müdür V.',
      'Kurul Başkanı',
      'Kurul Başkanı / Okul Müdürü',
      'Müdür Yardımcısı',
      'Zümre Başkanı',
      'Komisyon Başkanı',
      'Kurum Müdürü',
    ];

    Widget buildAuthorityNameField() {
      return _buildLabeledField(
        label: _authorityNameLabel,
        child: TextField(
          controller: _authorityNameController,
          style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
          decoration: _compactInputDecoration('Ad Soyad yazın veya seçin')
              .copyWith(
                suffixIcon: IconButton(
                  tooltip: 'Personel Listesinden Seç',
                  icon: Icon(
                    Icons.person_search_rounded,
                    size: 18,
                    color: Colors.indigo.shade700,
                  ),
                  onPressed: () => _openSinglePickerDialog(
                    title: _authorityNameLabel,
                    options: ctx.allStaff.map((s) => s.fullName).toList(),
                    subtitles: {
                      for (final s in ctx.allStaff)
                        s.fullName: s.branch.isNotEmpty ? s.branch : s.role,
                    },
                    current: _authorityNameController.text,
                    allowCustom: true,
                    onPicked: (val) {
                      _authorityNameController.text = val;
                      if (widget.template.id == 'sok_toplanti_tutanagi') {
                        _answers['chairPerson'] = val;
                      }
                      _recomposeFromTemplate();
                    },
                  ),
                ),
              ),
          onChanged: (val) {
            if (widget.template.id == 'sok_toplanti_tutanagi') {
              _answers['chairPerson'] = val.trim();
            }
            _recomposeFromTemplate();
          },
        ),
      );
    }

    Widget buildAuthorityTitleField() {
      return _buildLabeledField(
        label: _authorityTitleLabel,
        child: TextField(
          controller: _authorityTitleController,
          style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600),
          decoration: _compactInputDecoration(
            'Örn: Okul Müdürü, Müdür V., Kurul Başkanı',
          ),
          onChanged: (_) => _recomposeFromTemplate(),
        ),
      );
    }

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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  size: 16,
                  color: Colors.indigo.shade800,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Üst Antet, Kurum ve Yetkili Bilgileri',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Resmi evraktaki okul adını, müdür veya kurul başkanı bilgisini özelleştirin',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildAntetOption(
                  style: DocHeaderStyle.mebOfficial,
                  title: 'MEB Resmi Yazı Anteti',
                  subtitle: 'T.C. Kaymakamlık / Okul Md.',
                  icon: Icons.account_balance_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAntetOption(
                  style: DocHeaderStyle.corporateLogo,
                  title: 'Kurumsal Okul Anteti',
                  subtitle: 'Okul Adı & Dönem Başlığı',
                  icon: Icons.apartment_rounded,
                ),
              ),
            ],
          ),
          if (_headerStyle == DocHeaderStyle.mebOfficial) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildLabeledField(
                    label: 'İl (Valilik)',
                    child: TextField(
                      controller: _provinceController,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: _compactInputDecoration('Örn: ANKARA'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildLabeledField(
                    label: 'İlçe (Kaymakamlık)',
                    child: TextField(
                      controller: _districtController,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: _compactInputDecoration('Örn: ETİMESGUT'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _buildLabeledField(
            label: 'Evrakta Görünecek Resmi Okul / Kurum Adı',
            child: TextField(
              controller: _schoolNameController,
              style: const TextStyle(
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
              ),
              decoration: _compactInputDecoration(
                'Örn: Özel ABC Ortaokulu Müdürlüğü',
              ),
              onChanged: (_) => _recomposeFromTemplate(),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 460) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: buildAuthorityNameField()),
                    const SizedBox(width: 8),
                    Expanded(flex: 5, child: buildAuthorityTitleField()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildAuthorityNameField(),
                  const SizedBox(height: 8),
                  buildAuthorityTitleField(),
                ],
              );
            },
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: presetTitles.map((preset) {
              final isSelected =
                  _authorityTitleController.text.trim() == preset;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  _authorityTitleController.text = preset;
                  _recomposeFromTemplate();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.indigo.shade100
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? Colors.indigo.shade500
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    preset,
                    style: TextStyle(
                      fontSize: 10.8,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.indigo.shade900
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSignersConfigCard() {
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.draw_rounded,
                  size: 16,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alt İmza Bloğu ve Yetkililer',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'İmza sahiplerini ve unvanlarını dilediğiniz gibi düzenleyin veya ekleyin',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (_areSignersManuallyEdited)
                TextButton(
                  onPressed: () {
                    setState(() => _areSignersManuallyEdited = false);
                    _recomposeFromTemplate();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sıfırla',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if ((widget.template.id == 'sok_toplanti_tutanagi' ||
                  widget.template.id ==
                      'ilkogretim_sinif_gecme_tekrar_tutanagi') &&
              _answers['includeSokSignatureTable'] != false)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.table_rows_rounded,
                    size: 16,
                    color: Colors.indigo.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ŞÖK Öğretmen İmza Sirküsü Tablosu Aktif (${_resolveSignatureStaff().length} öğretmen): Ders öğretmenleri PDF çıktısında İmza Sirküsü Tablosu olarak basılır; alt imza bloğunda yalnızca Kurul Başkanı / Yetkili yer alır.',
                      style: TextStyle(
                        fontSize: 11.3,
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_signers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Henüz alt imza yetkilisi eklenmemiş. Aşağıdan ekleyebilirsiniz.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            for (int i = 0; i < _signers.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _signers[i].isApproval
                      ? Colors.amber.shade50.withValues(alpha: 0.6)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _signers[i].isApproval
                        ? Colors.amber.shade200
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _openSignerEditDialog(index: i),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _signers[i].name.isNotEmpty
                                  ? _signers[i].name
                                  : '(İsimsiz Yetkili)',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              _signers[i].title,
                              style: TextStyle(
                                fontSize: 11.2,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Düzenle',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 17,
                        color: Colors.indigo.shade700,
                      ),
                      onPressed: () => _openSignerEditDialog(index: i),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: Colors.red.shade400,
                      ),
                      onPressed: () {
                        setState(() {
                          _signers.removeAt(i);
                          _areSignersManuallyEdited = true;
                        });
                      },
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openSignerEditDialog(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text(
                'İmza / Onay Yetkilisi Ekle',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSignerEditDialog({int? index}) {
    final existing = index != null ? _signers[index] : null;
    final nameCtrl = TextEditingController(
      text: existing?.name ?? _authorityNameController.text,
    );
    final titleCtrl = TextEditingController(
      text: existing?.title ?? _authorityTitleController.text,
    );
    bool isApproval = existing?.isApproval ?? (index == null);
    final ctx = _ctx!;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            index == null ? 'İmza Yetkilisi Ekle' : 'İmza Bilgisini Düzenle',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabeledField(
                  label: 'Ad Soyad',
                  child: TextField(
                    controller: nameCtrl,
                    decoration: _compactInputDecoration('Ad Soyad').copyWith(
                      suffixIcon: IconButton(
                        tooltip: 'Personelden Seç',
                        icon: const Icon(Icons.person_search_rounded, size: 18),
                        onPressed: () => _openSinglePickerDialog(
                          title: 'Personel Seçin',
                          options: ctx.allStaff.map((s) => s.fullName).toList(),
                          subtitles: {
                            for (final s in ctx.allStaff)
                              s.fullName: s.branch.isNotEmpty
                                  ? s.branch
                                  : s.role,
                          },
                          current: nameCtrl.text,
                          allowCustom: true,
                          onPicked: (v) => setDlg(() => nameCtrl.text = v),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildLabeledField(
                  label:
                      'Unvan / Görev (Örn: Okul Müdürü, Kurul Başkanı, Yazman)',
                  child: TextField(
                    controller: titleCtrl,
                    decoration: _compactInputDecoration('Unvan yazın...'),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Üst Onay / OLUR Makamı (Alt ortada vurgulu basılır)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  value: isApproval,
                  onChanged: (v) => setDlg(() => isApproval = v),
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
              onPressed: () {
                final updated = DocSigner(
                  name: nameCtrl.text.trim(),
                  title: titleCtrl.text.trim().isNotEmpty
                      ? titleCtrl.text.trim()
                      : 'Yetkili',
                  isApproval: isApproval,
                );
                setState(() {
                  if (index != null) {
                    _signers[index] = updated;
                  } else {
                    _signers.add(updated);
                  }
                  _areSignersManuallyEdited = true;
                });
                Navigator.pop(dCtx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // İMZA SİRKÜSÜ ÖĞRETMEN / BRANŞ SEÇİMİ VE ELLE EKLEME PANELİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSignatureStaffConfigurator() {
    final pool = _allSignaturePoolStaff();
    final selectedCount = pool
        .where((s) => _selectedSigStaffIds.contains(_sigKey(s)))
        .length;

    // Branş / Zümre bazlı gruplama (Türkçe alfabetik sıralı)
    final Map<String, List<DocStaffItem>> byBranch = {};
    for (final s in pool) {
      final b = s.groupLabel;
      byBranch.putIfAbsent(b, () => []).add(s);
    }
    for (final cb in _customSigBranches) {
      if (cb.trim().isNotEmpty) {
        byBranch.putIfAbsent(cb.trim(), () => []);
      }
    }
    final sortedBranches = byBranch.keys.toList()..sort(_turkishCompare);
    final bQueryNorm = _normTr(_sigBranchSearch);
    final filteredBranches = bQueryNorm.isEmpty
        ? sortedBranches
        : sortedBranches.where((b) => _normTr(b).contains(bQueryNorm)).toList();

    final qNorm = _normTr(_sigStaffSearch);
    final filteredStaff = qNorm.isEmpty
        ? pool
        : pool
              .where(
                (s) =>
                    _normTr(s.fullName).contains(qNorm) ||
                    _normTr(s.groupLabel).contains(qNorm),
              )
              .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst Başlık + Seçili Sayısı + Elle Ekle Butonu
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add_check_circle_rounded,
                    size: 18,
                    color: Colors.indigo.shade800,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'İmza Sirküsü Katılımcı Seçimi',
                    style: TextStyle(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$selectedCount / ${pool.length} Seçili',
                      style: const TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => _openAddManualSigStaffDialog(),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                label: const Text(
                  'Elle Öğretmen / Branş Ekle',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo.shade900,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.indigo.shade300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Seçim Modu Sekmesi: Branşa Göre | Kişiye Göre + Tümünü Seç / Kaldır
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => setState(() => _sigFilterMode = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _sigFilterMode == 0
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.category_outlined,
                                  size: 14,
                                  color: _sigFilterMode == 0
                                      ? Colors.indigo.shade900
                                      : const Color(0xFF475569),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Zümre / Branşa Göre',
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w700,
                                    color: _sigFilterMode == 0
                                        ? Colors.indigo.shade900
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => setState(() => _sigFilterMode = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _sigFilterMode == 1
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_search_rounded,
                                  size: 14,
                                  color: _sigFilterMode == 1
                                      ? Colors.indigo.shade900
                                      : const Color(0xFF475569),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Kişiye Göre',
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w700,
                                    color: _sigFilterMode == 1
                                        ? Colors.indigo.shade900
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (selectedCount == pool.length && pool.isNotEmpty) {
                      _selectedSigStaffIds.clear();
                    } else {
                      for (final s in pool) {
                        _selectedSigStaffIds.add(_sigKey(s));
                      }
                    }
                  });
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  selectedCount == pool.length && pool.isNotEmpty
                      ? 'Tümünü Kaldır'
                      : 'Hepsini Seç',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // MOD 0: ZÜMRE / BRANŞA GÖRE ALT ALTA LİSTE SEÇİMİ
          if (_sigFilterMode == 0) ...[
            TextField(
              key: const ValueKey('sig_branch_search_field'),
              style: const TextStyle(fontSize: 12.5),
              decoration:
                  _compactInputDecoration(
                    'Zümre veya branş filtrele...',
                  ).copyWith(
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  ),
              onChanged: (v) => setState(() => _sigBranchSearch = v),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 270),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: filteredBranches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Eşleşen zümre / branş bulunamadı. Üstteki butondan elle ekleyebilirsiniz.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredBranches.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (_, idx) {
                        final branch = filteredBranches[idx];
                        final members = byBranch[branch] ?? const [];
                        final selInBranch = members
                            .where(
                              (m) => _selectedSigStaffIds.contains(_sigKey(m)),
                            )
                            .length;
                        final allOn =
                            members.isNotEmpty && selInBranch == members.length;
                        final partial =
                            selInBranch > 0 && selInBranch < members.length;
                        final activeRow = allOn || partial;

                        return InkWell(
                          onTap: () {
                            if (members.isEmpty) {
                              _openAddManualSigStaffDialog(
                                presetBranch: branch,
                              );
                              return;
                            }
                            setState(() {
                              if (allOn) {
                                for (final m in members) {
                                  _selectedSigStaffIds.remove(_sigKey(m));
                                }
                              } else {
                                for (final m in members) {
                                  _selectedSigStaffIds.add(_sigKey(m));
                                }
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  members.isEmpty
                                      ? Icons.add_circle_outline_rounded
                                      : allOn
                                      ? Icons.check_box_rounded
                                      : partial
                                      ? Icons.indeterminate_check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 19,
                                  color: allOn
                                      ? Colors.indigo.shade800
                                      : partial
                                      ? Colors.amber.shade800
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    branch,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: activeRow
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: (activeRow || members.isEmpty)
                                          ? const Color(0xFF0F172A)
                                          : Colors.grey.shade500,
                                      decoration:
                                          (!activeRow && members.isNotEmpty)
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: members.isEmpty
                                        ? const Color(0xFFECFDF5)
                                        : allOn
                                        ? Colors.indigo.shade50
                                        : partial
                                        ? Colors.amber.shade50
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    members.isEmpty
                                        ? '+ Öğretmen Ekle'
                                        : '$selInBranch / ${members.length} Seçili',
                                    style: TextStyle(
                                      fontSize: 10.8,
                                      fontWeight: FontWeight.w700,
                                      color: members.isEmpty
                                          ? const Color(0xFF047857)
                                          : allOn
                                          ? Colors.indigo.shade800
                                          : partial
                                          ? Colors.amber.shade900
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'İpucu: Bir zümre/branş satırına dokunarak o branştaki tüm öğretmenleri tek seferde çıkarıp ekleyebilir; tek tek öğretmen seçmek için "Kişiye Göre" sekmesine geçebilirsiniz.',
              style: TextStyle(fontSize: 10.8, color: Colors.grey.shade600),
            ),
          ]
          // MOD 1: KİŞİYE GÖRE SEÇİM
          else ...[
            TextField(
              key: const ValueKey('sig_staff_search_field'),
              style: const TextStyle(fontSize: 12.5),
              decoration:
                  _compactInputDecoration(
                    'Öğretmen adı veya branş filtrele...',
                  ).copyWith(
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  ),
              onChanged: (v) => setState(() => _sigStaffSearch = v),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 270),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: filteredStaff.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Eşleşen öğretmen bulunamadı. Üstteki butondan elle ekleyebilirsiniz.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredStaff.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      itemBuilder: (_, idx) {
                        final item = filteredStaff[idx];
                        final key = _sigKey(item);
                        final checked = _selectedSigStaffIds.contains(key);
                        return InkWell(
                          onTap: () {
                            setState(() {
                              checked
                                  ? _selectedSigStaffIds.remove(key)
                                  : _selectedSigStaffIds.add(key);
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  checked
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 19,
                                  color: checked
                                      ? Colors.indigo.shade800
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          item.fullName,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: checked
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: checked
                                                ? const Color(0xFF0F172A)
                                                : Colors.grey.shade500,
                                            decoration: checked
                                                ? null
                                                : TextDecoration.lineThrough,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (item.isCustom) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFA7F3D0),
                                            ),
                                          ),
                                          child: const Text(
                                            'ELLE',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF047857),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => _openEditStaffBranchDialog(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item.groupLabel,
                                          style: const TextStyle(
                                            fontSize: 10.8,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        const Icon(
                                          Icons.edit_outlined,
                                          size: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (item.isCustom) ...[
                                  const SizedBox(width: 2),
                                  IconButton(
                                    tooltip: 'Listeden Sil',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 26,
                                      minHeight: 26,
                                    ),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: Colors.red.shade400,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _customSigStaff.removeWhere(
                                          (c) => _sigKey(c) == key,
                                        );
                                        _selectedSigStaffIds.remove(key);
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _availableBranchSuggestions() {
    const commonMebBranches = <String>[
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'İngilizce',
      'Din Kültürü ve Ahlak Bilgisi',
      'Görsel Sanatlar',
      'Müzik',
      'Beden Eğitimi ve Spor',
      'Bilişim Teknolojileri',
      'Teknoloji ve Tasarım',
      'Rehberlik / PDR',
      'Sınıf Öğretmeni',
      'Okul Öncesi',
      'Müdür Yardımcısı',
    ];
    return <String>{
      ...(_ctx?.branches ?? const []),
      ..._customSigBranches,
      ...commonMebBranches,
    }.toList();
  }

  void _openAddManualSigStaffDialog({String? presetBranch}) {
    final nameCtrl = TextEditingController();
    final branchCtrl = TextEditingController(text: presetBranch ?? '');
    final branchSuggestions = _availableBranchSuggestions();
    int addedInSession = 0;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDlg) {
          bool addCurrent({required bool keepOpen}) {
            final name = nameCtrl.text.trim();
            final branch = branchCtrl.text.trim();

            if (name.isEmpty && branch.isNotEmpty && !keepOpen) {
              setState(() {
                _customSigBranches.add(branch);
              });
              return true;
            }
            if (name.isEmpty) return false;

            final effectiveBranch = branch.isNotEmpty ? branch : 'Öğretmen';
            final newItem = DocStaffItem(
              id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
              fullName: name,
              branch: effectiveBranch,
              role: effectiveBranch,
              isCustom: true,
            );
            setState(() {
              _customSigStaff.add(newItem);
              _selectedSigStaffIds.add(_sigKey(newItem));
              if (branch.isNotEmpty) {
                _customSigBranches.add(branch);
              }
            });
            if (keepOpen) {
              nameCtrl.clear();
              setDlg(() => addedInSession++);
            }
            return true;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Elle Öğretmen / Branş Ekle',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (addedInSession > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          '$addedInSession öğretmen imza listesine eklendi. Yeni isim yazmaya devam edebilirsiniz.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    _buildLabeledField(
                      label: 'Öğretmen / Personel Adı Soyadı',
                      helper:
                          'Sadece yeni branş tanımlamak isterseniz isim alanını boş bırakabilirsiniz',
                      child: TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        decoration: _compactInputDecoration('Örn: Ayşe Demir'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLabeledField(
                      label:
                          'Branşı / Görevi (Yazabilir veya Aşağıdan Seçebilirsiniz)',
                      child: TextField(
                        controller: branchCtrl,
                        decoration: _compactInputDecoration(
                          'Örn: Matematik, Görsel Sanatlar, Ücretli Öğretmen...',
                        ),
                        onChanged: (_) => setDlg(() {}),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: branchSuggestions.map((b) {
                        final selected = branchCtrl.text.trim() == b;
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setDlg(() => branchCtrl.text = b),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.indigo.shade100
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? Colors.indigo.shade400
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              b,
                              style: TextStyle(
                                fontSize: 10.8,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? Colors.indigo.shade900
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Kapat'),
              ),
              OutlinedButton(
                onPressed: () => addCurrent(keepOpen: true),
                child: const Text('Ekle & Yeni Yaz'),
              ),
              ElevatedButton(
                onPressed: () {
                  final ok = addCurrent(keepOpen: false);
                  if (ok || addedInSession > 0) {
                    Navigator.pop(dCtx);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade900,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Listeye Ekle'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openEditStaffBranchDialog(DocStaffItem item) {
    final branchCtrl = TextEditingController(text: item.groupLabel);
    final suggestions = _availableBranchSuggestions();
    final key = _sigKey(item);

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '${item.fullName} — Branş / Görev Düzenle',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: branchCtrl,
                    autofocus: true,
                    decoration: _compactInputDecoration('Branş / Görev yazın'),
                    onChanged: (_) => setDlg(() {}),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: suggestions.map((b) {
                      final sel = branchCtrl.text.trim() == b;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setDlg(() => branchCtrl.text = b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? Colors.indigo.shade100
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            b,
                            style: TextStyle(
                              fontSize: 10.8,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () {
                final val = branchCtrl.text.trim();
                if (val.isNotEmpty) {
                  setState(() {
                    if (item.isCustom) {
                      final idx = _customSigStaff.indexWhere(
                        (c) => _sigKey(c) == key,
                      );
                      if (idx != -1) {
                        _customSigStaff[idx] = _customSigStaff[idx].copyWith(
                          branch: val,
                          role: val,
                        );
                      }
                    } else {
                      _sigStaffBranchOverrides[key] = val;
                    }
                    _customSigBranches.add(val);
                  });
                }
                Navigator.pop(dCtx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade900,
                foregroundColor: Colors.white,
              ),
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAntetOption({
    required DocHeaderStyle style,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _headerStyle == style;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _headerStyle = style),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo.shade50 : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Colors.indigo.shade600 : const Color(0xFFE2E8F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.indigo.shade800 : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? Colors.indigo.shade900
                          : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.2,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionWidget(DocQuestionField q) {
    final ctx = _ctx!;

    switch (q.type) {
      case DocFieldType.text:
      case DocFieldType.multiline:
        final ctrl = _textControllers[q.key]!;
        return _buildLabeledField(
          label: q.label,
          helper: q.helperText,
          child: TextField(
            controller: ctrl,
            maxLines: q.type == DocFieldType.multiline ? 3 : 1,
            style: const TextStyle(fontSize: 13),
            decoration: _compactInputDecoration(q.hint ?? ''),
            onChanged: (v) => _updateAnswer(q.key, v),
          ),
        );

      case DocFieldType.date:
        final ctrl = _textControllers[q.key]!;
        return _buildLabeledField(
          label: q.label,
          child: TextField(
            controller: ctrl,
            readOnly: true,
            style: const TextStyle(fontSize: 13),
            decoration: _compactInputDecoration('gg.aa.yyyy').copyWith(
              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2032),
              );
              if (picked != null) {
                final formatted = DateFormat('dd.MM.yyyy').format(picked);
                ctrl.text = formatted;
                _updateAnswer(q.key, formatted);
              }
            },
          ),
        );

      case DocFieldType.time:
        final ctrl = _textControllers[q.key]!;
        return _buildLabeledField(
          label: q.label,
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration: _compactInputDecoration('SS:DD').copyWith(
              suffixIcon: IconButton(
                icon: const Icon(Icons.access_time_rounded, size: 17),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (picked != null) {
                    final formatted =
                        '${picked.hour.toString().padLeft(2, "0")}:${picked.minute.toString().padLeft(2, "0")}';
                    ctrl.text = formatted;
                    _updateAnswer(q.key, formatted);
                  }
                },
              ),
            ),
            onChanged: (v) => _updateAnswer(q.key, v),
          ),
        );

      case DocFieldType.dropdown:
        final current = (_answers[q.key] ?? '').toString();
        final opts = q.options.contains(current) || current.isEmpty
            ? q.options
            : [current, ...q.options];
        return _buildLabeledField(
          label: q.label,
          child: DropdownButtonFormField<String>(
            value: current.isNotEmpty
                ? current
                : (opts.isNotEmpty ? opts.first : null),
            isExpanded: true,
            decoration: _compactInputDecoration('Seçiniz'),
            style: const TextStyle(fontSize: 12.8, color: Color(0xFF0F172A)),
            items: opts
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _updateAnswer(q.key, v);
            },
          ),
        );

      case DocFieldType.yesNo:
        final val = _answers[q.key] == true;
        final switchTile = SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          tileColor: const Color(0xFFF8FAFC),
          title: Text(
            q.label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          value: val,
          activeTrackColor: Colors.indigo.shade700,
          onChanged: (v) => _updateAnswer(q.key, v),
        );
        if (q.key == 'includeStaffSignatureTable' && val) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              switchTile,
              const SizedBox(height: 10),
              _buildSignatureStaffConfigurator(),
            ],
          );
        }
        return switchTile;

      case DocFieldType.branchSelect:
        final current = (_answers[q.key] ?? '').toString();
        final branches = <String>{
          ...ctx.branches,
          if (current.isNotEmpty) current,
        }.toList();
        return _buildLabeledField(
          label: q.label,
          child: DropdownButtonFormField<String>(
            value: current.isNotEmpty
                ? current
                : (branches.isNotEmpty ? branches.first : null),
            isExpanded: true,
            decoration: _compactInputDecoration('Branş seçin'),
            items: branches
                .map(
                  (b) => DropdownMenuItem(
                    value: b,
                    child: Text(b, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) _updateAnswer(q.key, v);
            },
          ),
        );

      case DocFieldType.classSelect:
        final classNames = ctx.classes.map((c) => c.className).toList();
        final current = (_answers[q.key] ?? '').toString();
        final opts = <String>{
          ...classNames,
          if (current.isNotEmpty) current,
        }.toList();
        return _buildLabeledField(
          label: q.label,
          child: opts.isEmpty
              ? TextField(
                  decoration: _compactInputDecoration(
                    'Şube adı yazın (Örn: 7-A)',
                  ),
                  onChanged: (v) => _updateAnswer(q.key, v),
                )
              : DropdownButtonFormField<String>(
                  value: current.isNotEmpty ? current : opts.first,
                  isExpanded: true,
                  decoration: _compactInputDecoration('Şube seçin'),
                  items: opts
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null)
                      _updateAnswer(q.key, v, reloadStudents: true);
                  },
                ),
        );

      case DocFieldType.multiClassSelect:
        final selected = (_answers[q.key] is List)
            ? List<String>.from(
                (_answers[q.key] as List).map((e) => e.toString()),
              )
            : <String>[];
        return _buildLabeledField(
          label: q.label,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (ctx.classes.length > 1)
                ActionChip(
                  label: Text(
                    selected.length == ctx.classes.length
                        ? ' Seçimi Temizle'
                        : 'Tüm Şubeler',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: Colors.indigo.shade50,
                  onPressed: () {
                    final next = selected.length == ctx.classes.length
                        ? <String>[]
                        : ctx.classes.map((c) => c.className).toList();
                    _updateAnswer(q.key, next, reloadStudents: true);
                  },
                ),
              for (final cls in ctx.classes)
                FilterChip(
                  selected: selected.contains(cls.className),
                  label: Text(
                    cls.className,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selectedColor: Colors.indigo.shade100,
                  checkmarkColor: Colors.indigo.shade900,
                  onSelected: (on) {
                    final next = List<String>.from(selected);
                    on ? next.add(cls.className) : next.remove(cls.className);
                    _updateAnswer(q.key, next, reloadStudents: true);
                  },
                ),
            ],
          ),
        );

      case DocFieldType.staffSelect:
        final staffNames = ctx.allStaff.map((s) => s.fullName).toList();
        final current = (_answers[q.key] ?? '').toString();
        return _buildLabeledField(
          label: q.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openSinglePickerDialog(
              title: q.label,
              options: staffNames,
              subtitles: {
                for (final s in ctx.allStaff)
                  s.fullName: s.branch.isNotEmpty ? s.branch : s.role,
              },
              current: current,
              allowCustom: true,
              onPicked: (val) => _updateAnswer(q.key, val),
            ),
            child: _buildSelectorBox(
              current.isEmpty ? 'Personel / Öğretmen Seçin' : current,
              Icons.person_search_rounded,
            ),
          ),
        );

      case DocFieldType.multiStaffSelect:
        final selected = (_answers[q.key] is List)
            ? List<String>.from(
                (_answers[q.key] as List).map((e) => e.toString()),
              )
            : <String>[];
        return _buildLabeledField(
          label: q.label,
          helper: q.helperText,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openMultiPickerDialog(
              title: q.label,
              options: ctx.allStaff.map((s) => s.fullName).toList(),
              subtitles: {
                for (final s in ctx.allStaff)
                  s.fullName: s.branch.isNotEmpty ? s.branch : s.role,
              },
              initialSelected: selected,
              onConfirmed: (list) => _updateAnswer(q.key, list),
            ),
            child: _buildSelectorBox(
              selected.isEmpty
                  ? 'Öğretmen / Personel Seçin'
                  : '${selected.length} Kişi: ${selected.join(", ")}',
              Icons.group_add_rounded,
            ),
          ),
        );

      case DocFieldType.studentSelect:
        final current = (_answers[q.key] ?? '').toString();
        final names = _loadedStudents.map((s) => s.fullName).toList();
        return _buildLabeledField(
          label: q.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openSinglePickerDialog(
              title: q.label,
              options: names,
              subtitles: {
                for (final s in _loadedStudents)
                  s.fullName: '${s.className} • No: ${s.studentNo}',
              },
              current: current,
              allowCustom: true,
              onPicked: (val) => _updateAnswer(q.key, val),
            ),
            child: _buildSelectorBox(
              current.isEmpty ? 'Öğrenci Seçin (veya Manuel Yazın)' : current,
              Icons.school_outlined,
            ),
          ),
        );

      case DocFieldType.multiStudentSelect:
        final selected = (_answers[q.key] is List)
            ? List<String>.from(
                (_answers[q.key] as List).map((e) => e.toString()),
              )
            : <String>[];
        return _buildLabeledField(
          label: q.label,
          helper: q.helperText,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openMultiPickerDialog(
              title: q.label,
              options: _loadedStudents.map((s) => s.displayLabel).toList(),
              subtitles: const {},
              initialSelected: selected,
              onConfirmed: (list) => _updateAnswer(q.key, list),
            ),
            child: _buildSelectorBox(
              selected.isEmpty
                  ? 'Öğrenci(ler) Seçin'
                  : '${selected.length} Öğrenci Seçildi',
              Icons.groups_outlined,
            ),
          ),
        );

      case DocFieldType.multiCheck:
        final isSokTeachersField =
            widget.template.id == 'sok_toplanti_tutanagi' &&
            q.key == 'sokTeachers';
        final dynamicSokPool = isSokTeachersField
            ? (_ctx?.classTeachersByClass[(_answers['targetClass'] ?? '')
                      .toString()
                      .trim()] ??
                  const <String>[])
            : const <String>[];
        final selected = (_answers[q.key] is List)
            ? List<String>.from(
                (_answers[q.key] as List).map((e) => e.toString()),
              )
            : <String>[];
        final customPool = _customMultiCheckItems[q.key] ?? const <String>[];
        final allItems = <String>{
          ...q.options,
          ...dynamicSokPool,
          ...customPool,
          ...selected,
        }.toList();
        final searchVal = _normTr(_multiCheckSearch[q.key] ?? '');
        final filteredItems = searchVal.isEmpty
            ? allItems
            : allItems.where((it) => _normTr(it).contains(searchVal)).toList();
        final allSelected =
            allItems.isNotEmpty && selected.length >= allItems.length;

        return _buildLabeledField(
          label: q.label,
          helper: q.helperText,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Bilgi ve Toplu İşlem Çubuğu
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Text(
                        isSokTeachersField
                            ? '${selected.length} / ${allItems.length} Öğretmen Seçili'
                            : '${selected.length} / ${allItems.length} Madde Seçili',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        if (allSelected) {
                          _updateAnswer(q.key, <String>[]);
                        } else {
                          _updateAnswer(q.key, List<String>.from(allItems));
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          allSelected ? 'Tümünü Kaldır' : 'Tümünü Seç',
                          style: TextStyle(
                            fontSize: 11.2,
                            fontWeight: FontWeight.w700,
                            color: allSelected
                                ? Colors.red.shade700
                                : Colors.indigo.shade700,
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _showAddCustomItemDialog(
                        isSokTeachersField
                            ? 'ŞÖK Öğretmeni (Örn: AD SOYAD (İngilizce))'
                            : q.label,
                        (newItem) {
                          final customList = List<String>.from(
                            _customMultiCheckItems[q.key] ?? const <String>[],
                          );
                          if (!customList.contains(newItem) &&
                              !q.options.contains(newItem) &&
                              !dynamicSokPool.contains(newItem)) {
                            customList.add(newItem);
                            _customMultiCheckItems[q.key] = customList;
                          }
                          final next = List<String>.from(selected);
                          if (!next.contains(newItem)) next.add(newItem);
                          _updateAnswer(q.key, next);
                        },
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 13.5,
                              color: Colors.indigo.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isSokTeachersField
                                  ? 'Elle Öğretmen Ekle'
                                  : 'Özel Madde Ekle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (allItems.length >= 7) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (val) =>
                        setState(() => _multiCheckSearch[q.key] = val),
                    style: const TextStyle(fontSize: 11.8),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      hintText: isSokTeachersField
                          ? 'Öğretmen veya branş ara (${allItems.length} şube öğretmeni)...'
                          : 'Maddeler içinde hızlı ara (${allItems.length} hazır madde)...',
                      hintStyle: const TextStyle(
                        fontSize: 11.4,
                        color: Color(0xFF94A3B8),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 30,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (filteredItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Text(
                      'Aramanızla eşleşen madde bulunamadı. Üstteki "+ Özel Madde Ekle" butonuyla yeni madde ekleyebilirsiniz.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                for (int idx = 0; idx < filteredItems.length; idx++)
                  Builder(
                    builder: (_) {
                      final item = filteredItems[idx];
                      final isChecked = selected.contains(item);
                      final isCustom =
                          !q.options.contains(item) &&
                          !dynamicSokPool.contains(item);
                      final originalIndex = allItems.indexOf(item) + 1;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? Colors.indigo.withValues(alpha: 0.055)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () {
                            final next = List<String>.from(selected);
                            isChecked ? next.remove(item) : next.add(item);
                            _updateAnswer(q.key, next);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 5,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isChecked
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18,
                                  color: isChecked
                                      ? Colors.indigo.shade800
                                      : Colors.grey.shade500,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    '$originalIndex. $item',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.32,
                                      fontWeight: isChecked
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: const Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                if (isCustom)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _customMultiCheckItems[q.key]?.remove(
                                          item,
                                        );
                                      });
                                      final next = List<String>.from(selected)
                                        ..remove(item);
                                      _updateAnswer(q.key, next);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 15,
                                        color: Colors.red.shade400,
                                      ),
                                    ),
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
          ),
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAĞ PANEL: CANLI RESMİ EVRAK ÖNİZLEME VE METİN DÜZENLEME
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildPreviewEditorPane() {
    final isSpecialLayout =
        widget.template.layoutKind == DocLayoutKind.dynamicChecklist ||
        widget.template.layoutKind == DocLayoutKind.badgeGrid;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: Colors.indigo.shade800,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Canlı Resmi Evrak Metni (Düzenlenebilir)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (_isBodyManuallyEdited)
                    TextButton.icon(
                      onPressed: () => _recomposeFromTemplate(force: true),
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text(
                        'Şablondan Yenile',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
              const Divider(height: 18),
              // Canlı Antet Önizleme Şeridi
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (_headerStyle == DocHeaderStyle.mebOfficial) ...[
                      const Text(
                        'T.C.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                      if (_provinceController.text.isNotEmpty ||
                          _districtController.text.isNotEmpty)
                        Text(
                          [
                            if (_provinceController.text.trim().isNotEmpty)
                              '${_trUpper(_provinceController.text.trim())} VALİLİĞİ',
                            if (_districtController.text.trim().isNotEmpty)
                              '${_trUpper(_districtController.text.trim())} KAYMAKAMLIĞI',
                          ].join(' / '),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                    Text(
                      _trUpper(_schoolNameController.text),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Colors.indigo.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isSpecialLayout)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bu şablon tablo / kart mizanpajındadır. Seçtiğiniz şube veya personel listesi (${_loadedStudents.isNotEmpty ? "${_loadedStudents.length} öğrenci" : "otomatik liste"}) "PDF Hazırla & Yazdır" butonuna bastığınızda A4 sayfaya otomatik yerleştirilir.',
                          style: const TextStyle(
                            fontSize: 12.2,
                            color: Color(0xFF065F46),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                TextField(
                  controller: _bodyController,
                  maxLines: 17,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.48,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFFCFDFF),
                    hintText:
                        'Resmi evrak metni burada oluşur; istediğiniz kelimeyi doğrudan düzenleyebilirsiniz...',
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  onChanged: (_) {
                    if (!_isBodyManuallyEdited) {
                      setState(() => _isBodyManuallyEdited = true);
                    }
                  },
                ),
              if (!isSpecialLayout) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Alt İmza Bloğu (Düzenlemek için üzerine dokunun)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openSignerEditDialog(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text(
                        'İmza Ekle',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int idx = 0; idx < _signers.length; idx++)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openSignerEditDialog(index: idx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _signers[idx].isApproval
                                ? Colors.amber.shade50
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _signers[idx].isApproval
                                  ? Colors.amber.shade200
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _signers[idx].title,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    _signers[idx].name,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.edit_outlined,
                                size: 13,
                                color: Colors.indigo.shade600,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YARDIMCI SEÇİM PENCERELERİ VE GİRİŞ STİLLERİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildLabeledField({
    required String label,
    String? helper,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        if (helper != null && helper.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            helper,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
        const SizedBox(height: 5),
        child,
      ],
    );
  }

  Widget _buildSelectorBox(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
        ],
      ),
    );
  }

  InputDecoration _compactInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.2, color: Color(0xFF94A3B8)),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.indigo.shade700, width: 1.4),
      ),
    );
  }

  void _showAddCustomItemDialog(
    String fieldTitle,
    ValueChanged<String> onAdded,
  ) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Özel Madde Ekle',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: _compactInputDecoration('Eklenecek cümleyi yazın...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) onAdded(v);
              Navigator.pop(dCtx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _openSinglePickerDialog({
    required String title,
    required List<String> options,
    required Map<String, String> subtitles,
    required String current,
    required bool allowCustom,
    required ValueChanged<String> onPicked,
  }) {
    String query = '';
    final manualCtrl = TextEditingController(text: current);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sCtx) => StatefulBuilder(
        builder: (sCtx, setSheet) {
          final filtered = options
              .where((o) => o.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sCtx).viewInsets.bottom + 14,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: _compactInputDecoration('Listede ara...')
                          .copyWith(
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                            ),
                          ),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Kayıt bulunamadı; aşağıdan manuel yazabilirsiniz.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (allowCustom) ...[
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: manualCtrl,
                                      decoration: _compactInputDecoration(
                                        'Ad Soyad yazın...',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () {
                                        if (manualCtrl.text.trim().isNotEmpty) {
                                          onPicked(manualCtrl.text.trim());
                                          Navigator.pop(sCtx);
                                        }
                                      },
                                      child: const Text('Manuel İsim Kullan'),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final item = filtered[idx];
                                final sub = subtitles[item] ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: sub.isNotEmpty
                                      ? Text(
                                          sub,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                          ),
                                        )
                                      : null,
                                  trailing: item == current
                                      ? Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.indigo.shade800,
                                          size: 18,
                                        )
                                      : null,
                                  onTap: () {
                                    onPicked(item);
                                    Navigator.pop(sCtx);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openMultiPickerDialog({
    required String title,
    required List<String> options,
    required Map<String, String> subtitles,
    required List<String> initialSelected,
    required ValueChanged<List<String>> onConfirmed,
  }) {
    String query = '';
    final temp = Set<String>.from(initialSelected);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sCtx) => StatefulBuilder(
        builder: (sCtx, setSheet) {
          final filtered = options
              .where((o) => o.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                MediaQuery.of(sCtx).viewInsets.bottom + 14,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.68,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheet(() {
                              if (temp.length == options.length) {
                                temp.clear();
                              } else {
                                temp.addAll(options);
                              }
                            });
                          },
                          child: Text(
                            temp.length == options.length
                                ? 'Temizle'
                                : 'Tümünü Seç',
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      decoration: _compactInputDecoration('Listede ara...')
                          .copyWith(
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                            ),
                          ),
                      onChanged: (v) => setSheet(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, idx) {
                          final item = filtered[idx];
                          final sub = subtitles[item] ?? '';
                          final checked = temp.contains(item);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            activeColor: Colors.indigo.shade800,
                            title: Text(
                              item,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: sub.isNotEmpty
                                ? Text(
                                    sub,
                                    style: const TextStyle(fontSize: 11.5),
                                  )
                                : null,
                            onChanged: (v) => setSheet(() {
                              v == true ? temp.add(item) : temp.remove(item);
                            }),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          onConfirmed(options.where(temp.contains).toList());
                          Navigator.pop(sCtx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        child: Text(
                          'Seçimi Uygula (${temp.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
