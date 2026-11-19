import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/school/student_movement_model.dart';
import '../../../../services/student_movement_pdf_service.dart';
import '../../../../services/student_movement_service.dart';
import '../../../../widgets/edukn_app_bar.dart';

class StudentMovementHubScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final int initialTabIndex;
  final bool isSecurityPortalMode;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const StudentMovementHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialTabIndex = 0,
    this.isSecurityPortalMode = false,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: EduknAppBar(
        title: isSecurityPortalMode
            ? 'Güvenlik Kapı & Öğrenci Çıkış Onayı'
            : 'Geç • İzin • Erken Alma • Revir • Görüşme',
        subtitle: schoolTypeName.isNotEmpty
            ? schoolTypeName
            : 'Anlık Öğrenci Hareket, Veli Çağrı ve İzleme Sistemi',
      ),
      body: StudentMovementHubBody(
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
        schoolTypeName: schoolTypeName,
        initialTabIndex: initialTabIndex,
        isSecurityPortalMode: isSecurityPortalMode,
        isTeacher: isTeacher,
        teacherId: teacherId,
        allowedClassIds: allowedClassIds,
      ),
    );
  }
}

class StudentMovementHubBody extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final int initialTabIndex;
  final bool isSecurityPortalMode;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const StudentMovementHubBody({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialTabIndex = 0,
    this.isSecurityPortalMode = false,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  });

  @override
  State<StudentMovementHubBody> createState() => _StudentMovementHubBodyState();
}

class _StudentMovementHubBodyState extends State<StudentMovementHubBody> {
  final StudentMovementService _service = StudentMovementService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late int _activeTab;
  bool _isBootstrapping = true;
  bool _isSubmitting = false;

  String _schoolDocId = '';
  String _schoolFullName = '';

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];

  // İzleme Ekranı Filtreleri
  DateTime _monitorDate = DateTime.now();
  final TextEditingController _monitorSearchCtrl = TextEditingController();
  String _monitorSearch = '';
  String _monitorClassFilter = '';
  StudentMovementType? _monitorTypeFilter;
  Timer? _minuteTicker;

  // Güvenlik Kapı Çıkış Onayı Arama Filtresi
  final TextEditingController _securitySearchCtrl = TextEditingController();
  String _securitySearchQuery = '';

  // Ortak ÇOKLU Öğrenci & Ders Seçimi Durumu
  String _selectedClassId = '';
  final List<Map<String, dynamic>> _selectedStudents = [];
  final TextEditingController _studentSearchCtrl = TextEditingController();
  String _studentSearchQuery = '';
  List<ResolvedLessonSlot> _resolvedSlots = [];
  int _selectedLessonHour = 1;
  int _liveCurrentLessonHour = 1;
  Set<int> _selectedInterviewHours = {1};
  bool _loadingSchedule = false;

  final Map<String, Map<StudentMovementType, int>> _studentCountsCache = {};
  final Map<
    String,
    ({
      int currentLessonHour,
      int maxLessonHour,
      String periodId,
      List<ResolvedLessonSlot> slots,
    })
  > _scheduleCache = {};

  // 1) Geç Kağıdı Form Durumu
  String _lateReason = 'Servis / Ulaşım Gecikmesi';
  final TextEditingController _lateNotesCtrl = TextEditingController();
  bool _lateAutoAttendance = true;

  // 2) Çıkış İzni Form Durumu
  String _exitMode = 'Veli Eşliğinde Çıkış';
  final TextEditingController _exitReasonCtrl =
      TextEditingController(text: 'Veli talebi / Sağlık mazereti');
  final TextEditingController _receiverNameCtrl = TextEditingController();
  final TextEditingController _receiverRelationCtrl =
      TextEditingController(text: 'Velisi');
  final TextEditingController _receiverPhoneCtrl = TextEditingController();
  final TextEditingController _plannedExitTimeCtrl = TextEditingController();
  final TextEditingController _exitNotesCtrl = TextEditingController();

  // 2.5) Erken Alma & Veli Çağrı Form Durumu
  bool _earlyArrivedNow = false;
  String _earlyRelation = 'Velisi';
  String _earlyReason = 'Hastane / Doktor / Diş Hekimi Randevusu';
  final TextEditingController _earlyReceiverNameCtrl = TextEditingController();
  final TextEditingController _earlyReceiverPhoneCtrl = TextEditingController();
  final TextEditingController _earlyPlateCtrl = TextEditingController();
  final TextEditingController _earlyPlannedTimeCtrl = TextEditingController();
  final TextEditingController _earlyNotesCtrl = TextEditingController();

  // 3) Revir Sevk Form Durumu
  final TextEditingController _infirmaryComplaintCtrl = TextEditingController();
  String _infirmaryUrgency = 'Normal';
  final TextEditingController _infirmaryNotesCtrl = TextEditingController();

  // 4) Görüşme Form Durumu
  String _interviewUnit = 'Rehberlik / PDR Servisi Görüşmesi';
  final TextEditingController _interviewerNameCtrl = TextEditingController();
  final TextEditingController _interviewTopicCtrl =
      TextEditingController(text: 'Bireysel / grup öğrenci görüşmesi');
  final TextEditingController _interviewNotesCtrl = TextEditingController();
  bool _interviewProtectAttendance = true;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTabIndex.clamp(0, 5);
    final now = DateTime.now();
    _plannedExitTimeCtrl.text = DateFormat('HH:mm').format(now);
    _earlyPlannedTimeCtrl.text =
        DateFormat('HH:mm').format(now.add(const Duration(minutes: 30)));
    final estHour = now.hour < 9
        ? 1
        : (((now.hour * 60 + now.minute - 9 * 60) ~/ 50) + 1).clamp(1, 8);
    _selectedLessonHour = estHour;
    _liveCurrentLessonHour = estHour;
    _selectedInterviewHours = {estHour};
    _resolvedSlots = _defaultLessonSlots(8);

    _bootstrap();
    _minuteTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    _monitorSearchCtrl.dispose();
    _securitySearchCtrl.dispose();
    _studentSearchCtrl.dispose();
    _lateNotesCtrl.dispose();
    _exitReasonCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverRelationCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _plannedExitTimeCtrl.dispose();
    _exitNotesCtrl.dispose();
    _earlyReceiverNameCtrl.dispose();
    _earlyReceiverPhoneCtrl.dispose();
    _earlyPlateCtrl.dispose();
    _earlyPlannedTimeCtrl.dispose();
    _earlyNotesCtrl.dispose();
    _infirmaryComplaintCtrl.dispose();
    _infirmaryNotesCtrl.dispose();
    _interviewerNameCtrl.dispose();
    _interviewTopicCtrl.dispose();
    _interviewNotesCtrl.dispose();
    super.dispose();
  }

  static List<ResolvedLessonSlot> _defaultLessonSlots(int count) {
    final dayName = StudentMovementService.dayNameTr(DateTime.now().weekday);
    return List<ResolvedLessonSlot>.generate(
      count,
      (i) {
        final startMin = 9 * 60 + i * 50;
        final endMin = startMin + 40;
        final sH = (startMin ~/ 60).toString().padLeft(2, '0');
        final sM = (startMin % 60).toString().padLeft(2, '0');
        final eH = (endMin ~/ 60).toString().padLeft(2, '0');
        final eM = (endMin % 60).toString().padLeft(2, '0');
        return ResolvedLessonSlot(
          lessonHour: i + 1,
          lessonId: '',
          lessonName: '${i + 1}. Ders',
          startTime: '$sH:$sM',
          endTime: '$eH:$eM',
          scheduleDayName: dayName,
        );
      },
    );
  }

  List<String> get _instVariants => {
        widget.institutionId.trim(),
        widget.institutionId.trim().toUpperCase(),
        widget.institutionId.trim().toLowerCase(),
      }.where((e) => e.isNotEmpty).toList();

  Future<void> _bootstrap() async {
    try {
      final actor = await _service.resolveCurrentActor();
      final schoolDocId =
          await _service.resolveSchoolDocId(widget.institutionId);

      String schoolName = widget.schoolTypeName;
      try {
        final sDoc = await _db.collection('schools').doc(schoolDocId).get();
        if (sDoc.exists) {
          final sd = sDoc.data() ?? {};
          final raw = (sd['schoolName'] ?? sd['name'] ?? '').toString().trim();
          if (raw.isNotEmpty) {
            schoolName = widget.schoolTypeName.isNotEmpty &&
                    !raw
                        .toLowerCase()
                        .contains(widget.schoolTypeName.toLowerCase())
                ? '$raw ${widget.schoolTypeName}'
                : raw;
          }
        }
      } catch (_) {}

      // Güvenlik Kapı Çıkış Onayı modunda sınıf/öğrenci/ders programı yüklemeye gerek yoktur; ekran doğrudan açılır.
      if (widget.isSecurityPortalMode) {
        if (!mounted) return;
        setState(() {
          _schoolDocId = schoolDocId;
          _schoolFullName =
              schoolName.isNotEmpty ? schoolName : 'Okul Müdürlüğü';
          _isBootstrapping = false;
        });
        return;
      }

      // Sınıfları yükle
      Query<Map<String, dynamic>> clsQuery = _db
          .collection('classes')
          .where('institutionId', whereIn: _instVariants)
          .where('isActive', isEqualTo: true);
      if (widget.schoolTypeId.isNotEmpty) {
        clsQuery =
            clsQuery.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
      }
      final clsSnap = await clsQuery.get();
      final classMapById = <String, String>{};
      var loadedClasses = clsSnap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        classMapById[d.id] = (m['className'] ?? '').toString();
        return m;
      }).toList();

      if (widget.allowedClassIds != null &&
          widget.allowedClassIds!.isNotEmpty) {
        final allowed = widget.allowedClassIds!.toSet();
        loadedClasses = loadedClasses
            .where((c) => allowed.contains((c['id'] ?? '').toString()))
            .toList();
      }

      loadedClasses.sort((a, b) {
        final la = int.tryParse((a['classLevel'] ?? '0').toString()) ?? 0;
        final lb = int.tryParse((b['classLevel'] ?? '0').toString()) ?? 0;
        final cmp = la.compareTo(lb);
        return cmp != 0
            ? cmp
            : (a['className'] ?? '')
                .toString()
                .compareTo((b['className'] ?? '').toString());
      });

      // Öğrencileri yükle
      Query<Map<String, dynamic>> stQuery = _db
          .collection('students')
          .where('institutionId', whereIn: _instVariants)
          .where('isActive', isEqualTo: true);
      if (widget.schoolTypeId.isNotEmpty) {
        stQuery = stQuery.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
      }
      final stSnap = await stQuery.get();
      final allowedClassIdSet = loadedClasses
          .map((c) => (c['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      final loadedStudents = stSnap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        final cid = (m['classId'] ?? '').toString();
        if ((m['className'] ?? '').toString().trim().isEmpty &&
            classMapById.containsKey(cid)) {
          m['className'] = classMapById[cid];
        }
        return m;
      }).where((s) {
        if (widget.allowedClassIds != null &&
            widget.allowedClassIds!.isNotEmpty) {
          return allowedClassIdSet.contains((s['classId'] ?? '').toString());
        }
        if (widget.schoolTypeId.isEmpty || classMapById.isEmpty) return true;
        final cid = (s['classId'] ?? '').toString();
        final stId = (s['schoolTypeId'] ?? '').toString();
        return stId == widget.schoolTypeId || classMapById.containsKey(cid);
      }).toList()
        ..sort(
          (a, b) => _studentDisplayName(a).compareTo(_studentDisplayName(b)),
        );

      // Başlangıçta kurumun aktif dönem ve günlük ders saat çizelgesini (workPeriods) yükle
      await _primeGeneralHours();

      if (!mounted) return;
      setState(() {
        _schoolDocId = schoolDocId;
        _schoolFullName =
            schoolName.isNotEmpty ? schoolName : 'Okul Müdürlüğü';
        _interviewerNameCtrl.text = actor.name;
        _classes = loadedClasses;
        _students = loadedStudents;
        _isBootstrapping = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBootstrapping = false);
    }
  }

  Future<void> _primeGeneralHours({String classId = ''}) async {
    try {
      final sched = await _service
          .resolveTodayScheduleForStudent(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            classId: classId,
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted || _selectedStudents.isNotEmpty) return;
      setState(() {
        if (sched.slots.isNotEmpty) {
          _resolvedSlots = sched.slots;
          _liveCurrentLessonHour = sched.currentLessonHour;
          _selectedLessonHour = sched.currentLessonHour;
          _selectedInterviewHours = {sched.currentLessonHour};
        }
      });
    } catch (_) {}
  }

  Future<void> _onClassFilterChanged(String newClassId) async {
    setState(() => _selectedClassId = newClassId);
    if (_selectedStudents.isNotEmpty) return;
    setState(() => _loadingSchedule = true);
    try {
      await _primeGeneralHours(classId: newClassId);
    } finally {
      if (mounted) {
        setState(() => _loadingSchedule = false);
      }
    }
  }

  static String _studentDisplayName(Map<String, dynamic> s) {
    final full = (s['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${s['name'] ?? s['firstName'] ?? ''} ${s['surname'] ?? s['lastName'] ?? ''}'
        .trim();
  }

  static String _studentNo(Map<String, dynamic> s) {
    return (s['studentNo'] ?? s['studentNumber'] ?? s['number'] ?? '')
        .toString()
        .trim();
  }

  static ({String name, String phone, String relation}) _extractParentInfo(
    Map<String, dynamic> student,
  ) {
    String pName = (student['parentName'] ?? '').toString().trim();
    String pPhone = (student['parentPhone'] ?? '').toString().trim();
    String pRel = 'Velisi';
    if (student['parents'] is Iterable &&
        (student['parents'] as Iterable).isNotEmpty) {
      final p = (student['parents'] as Iterable).first;
      if (p is Map) {
        if (pName.isEmpty) {
          pName = '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim();
        }
        if (pPhone.isEmpty) {
          pPhone = (p['phone'] ?? '').toString().trim();
        }
        final rel = (p['relation'] ?? '').toString().trim();
        if (rel.isNotEmpty) pRel = rel;
      }
    }
    return (name: pName, phone: pPhone, relation: pRel);
  }

  static String _normTr(String s) {
    return s
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

  bool _isStudentSelected(Map<String, dynamic> st) {
    final id = (st['id'] ?? '').toString();
    return _selectedStudents.any((s) => (s['id'] ?? '').toString() == id);
  }

  Set<String> get _selectedDistinctClassNames {
    return _selectedStudents
        .map((s) => (s['className'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toSet();
  }

  bool get _hasMultiClassSelection => _selectedDistinctClassNames.length > 1;

  Future<
      ({
        int currentLessonHour,
        int maxLessonHour,
        String periodId,
        List<ResolvedLessonSlot> slots,
      })> _resolveScheduleCached(Map<String, dynamic> student) async {
    final studentId = (student['id'] ?? '').toString();
    final classId = (student['classId'] ?? '').toString();
    final cacheKey = '${classId}_$studentId';
    if (_scheduleCache.containsKey(cacheKey)) {
      return _scheduleCache[cacheKey]!;
    }
    try {
      final res = await _service
          .resolveTodayScheduleForStudent(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            classId: classId,
            studentId: studentId,
          )
          .timeout(const Duration(seconds: 7));
      _scheduleCache[cacheKey] = res;
      return res;
    } catch (_) {
      return (
        currentLessonHour: _selectedLessonHour,
        maxLessonHour: _resolvedSlots.isNotEmpty ? _resolvedSlots.length : 8,
        periodId: '',
        slots: _resolvedSlots.isNotEmpty
            ? _resolvedSlots
            : _defaultLessonSlots(8),
      );
    }
  }

  Future<void> _toggleStudentSelection(Map<String, dynamic> student) async {
    final id = (student['id'] ?? '').toString();
    final existingIdx =
        _selectedStudents.indexWhere((s) => (s['id'] ?? '').toString() == id);

    setState(() {
      if (existingIdx >= 0) {
        _selectedStudents.removeAt(existingIdx);
      } else {
        _selectedStudents.add(student);
      }
      _plannedExitTimeCtrl.text = DateFormat('HH:mm').format(DateTime.now());
      if (_selectedStudents.length == 1) {
        final parent = _extractParentInfo(_selectedStudents.first);
        if (parent.name.isNotEmpty) {
          _receiverNameCtrl.text = parent.name;
          _earlyReceiverNameCtrl.text = parent.name;
        }
        if (parent.phone.isNotEmpty) {
          _receiverPhoneCtrl.text = parent.phone;
          _earlyReceiverPhoneCtrl.text = parent.phone;
        }
        _receiverRelationCtrl.text = parent.relation;
      } else if (_selectedStudents.isEmpty) {
        _receiverNameCtrl.clear();
        _receiverPhoneCtrl.clear();
        _earlyReceiverNameCtrl.clear();
        _earlyReceiverPhoneCtrl.clear();
      }
    });

    if (_selectedStudents.isEmpty) {
      _primeGeneralHours(classId: _selectedClassId);
      return;
    }

    // Seçili öğrencilerin geçmiş sayaçlarını ve referans ders programını güvenli şekilde yükle
    final anchorStudent = _selectedStudents.first;
    final anchorId = (anchorStudent['id'] ?? '').toString();
    final bool wasEmptyBefore = existingIdx < 0 && _selectedStudents.length == 1;

    setState(() => _loadingSchedule = true);
    try {
      final schedFuture = _resolveScheduleCached(anchorStudent);
      if (!_studentCountsCache.containsKey(id) && existingIdx < 0) {
        _service
            .getStudentMovementCounts(
              schoolDocId: _schoolDocId,
              studentId: id,
            )
            .timeout(const Duration(seconds: 5))
            .then((counts) {
              if (!mounted) return;
              setState(() => _studentCountsCache[id] = counts);
            })
            .catchError((_) {});
      }
      if (!_studentCountsCache.containsKey(anchorId)) {
        _service
            .getStudentMovementCounts(
              schoolDocId: _schoolDocId,
              studentId: anchorId,
            )
            .timeout(const Duration(seconds: 5))
            .then((counts) {
              if (!mounted) return;
              setState(() => _studentCountsCache[anchorId] = counts);
            })
            .catchError((_) {});
      }

      final sched = await schedFuture;
      if (!mounted) return;
      setState(() {
        if (sched.slots.isNotEmpty) {
          _resolvedSlots = sched.slots;
        }
        _liveCurrentLessonHour = sched.currentLessonHour;
        final validHours = _resolvedSlots.map((s) => s.lessonHour).toSet();
        if (wasEmptyBefore || !validHours.contains(_selectedLessonHour)) {
          _selectedLessonHour = sched.currentLessonHour;
        }
        _selectedInterviewHours = _selectedInterviewHours
            .where((h) => validHours.contains(h))
            .toSet();
        if (wasEmptyBefore || _selectedInterviewHours.isEmpty) {
          _selectedInterviewHours = {sched.currentLessonHour};
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loadingSchedule = false);
      }
    }
  }

  Future<void> _selectVisibleStudents(List<Map<String, dynamic>> visible) async {
    if (visible.isEmpty) return;
    final existingIds =
        _selectedStudents.map((s) => (s['id'] ?? '').toString()).toSet();
    final bool wasEmpty = _selectedStudents.isEmpty;
    setState(() {
      for (final st in visible) {
        final sid = (st['id'] ?? '').toString();
        if (!existingIds.contains(sid)) {
          _selectedStudents.add(st);
          existingIds.add(sid);
        }
      }
      if (_selectedStudents.length == 1) {
        final p = _extractParentInfo(_selectedStudents.first);
        if (p.name.isNotEmpty) _receiverNameCtrl.text = p.name;
        if (p.phone.isNotEmpty) _receiverPhoneCtrl.text = p.phone;
        _receiverRelationCtrl.text = p.relation;
      }
    });

    if (_selectedStudents.isNotEmpty) {
      setState(() => _loadingSchedule = true);
      try {
        final sched = await _resolveScheduleCached(_selectedStudents.first);
        if (!mounted) return;
        setState(() {
          if (sched.slots.isNotEmpty) _resolvedSlots = sched.slots;
          _liveCurrentLessonHour = sched.currentLessonHour;
          final validHours = _resolvedSlots.map((s) => s.lessonHour).toSet();
          if (wasEmpty || !validHours.contains(_selectedLessonHour)) {
            _selectedLessonHour = sched.currentLessonHour;
          }
          _selectedInterviewHours = _selectedInterviewHours
              .where((h) => validHours.contains(h))
              .toSet();
          if (wasEmpty || _selectedInterviewHours.isEmpty) {
            _selectedInterviewHours = {sched.currentLessonHour};
          }
        });
      } finally {
        if (mounted) setState(() => _loadingSchedule = false);
      }
    }
  }

  void _clearSelectedStudents() {
    setState(() {
      _selectedStudents.clear();
      _receiverNameCtrl.clear();
      _receiverPhoneCtrl.clear();
      _earlyReceiverNameCtrl.clear();
      _earlyReceiverPhoneCtrl.clear();
    });
    _primeGeneralHours(classId: _selectedClassId);
  }

  ResolvedLessonSlot _slotForHourFrom(
    List<ResolvedLessonSlot> slots,
    int hour,
  ) {
    final match = slots.where((s) => s.lessonHour == hour);
    if (match.isNotEmpty) return match.first;
    return ResolvedLessonSlot(
      lessonHour: hour,
      lessonId: '',
      lessonName: '$hour. Ders',
    );
  }

  ResolvedLessonSlot get _currentSelectedSlot =>
      _slotForHourFrom(_resolvedSlots, _selectedLessonHour);

  Future<void> _printSlip(StudentMovementRecord record) async {
    await _printBatchSlips([record]);
  }

  Future<void> _printBatchSlips(List<StudentMovementRecord> records) async {
    if (records.isEmpty) return;
    try {
      final bytes = await StudentMovementPdfService.generateBatchSlipsPdf(
        records: records,
        schoolName: _schoolFullName,
      );
      final first = records.first;
      final fileName = records.length == 1
          ? '${first.type.shortLabel}_${first.studentName}_${first.dateStr}.pdf'
          : '${first.type.shortLabel}_Toplu_${records.length}_Ogrenci_${first.dateStr}.pdf';
      await Printing.layoutPdf(
        name: fileName,
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF oluşturulurken hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _printDailyReport(List<StudentMovementRecord> records) async {
    try {
      final bytes = await StudentMovementPdfService.generateDailyReportPdf(
        records: records,
        schoolName: _schoolFullName,
        dateLabel: DateFormat('dd.MM.yyyy').format(_monitorDate),
      );
      await Printing.layoutPdf(
        name:
            'Ogrenci_Hareket_Raporu_${StudentMovementService.formatDateYmd(_monitorDate)}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rapor hatası: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showBatchSuccessActionSheet(
    List<StudentMovementRecord> records,
    String summaryText,
  ) {
    if (records.isEmpty) return;
    final first = records.first;
    final isMulti = records.length > 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: first.type.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.verified_rounded,
                      color: first.type.color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMulti
                              ? '${records.length} Öğrenci İçin ${first.type.fullTitle} Kaydedildi!'
                              : '${first.type.fullTitle} Kaydedildi!',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isMulti
                              ? records
                                  .take(4)
                                  .map((r) => '${r.studentName} (${r.className})')
                                  .join(' • ') +
                                  (records.length > 4
                                      ? ' +${records.length - 4} öğrenci daha'
                                      : '')
                              : '${first.studentName} (${first.className})',
                          style: GoogleFonts.inter(
                            fontSize: 12.8,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  summaryText,
                  style: GoogleFonts.inter(
                    fontSize: 12.6,
                    color: const Color(0xFF334155),
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _activeTab = 0);
                      },
                      icon: const Icon(Icons.radar_rounded, size: 18),
                      label: const Text(
                        'Canlı İzlemeye Git',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _printBatchSlips(records);
                      },
                      icon: const Icon(
                        Icons.print_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: Text(
                        isMulti
                            ? 'Tüm Pusulaları Yazdır (${records.length})'
                            : 'Kağıdı / Pusulayı Yazdır',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: first.type.color,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ÇOKLU ÖĞRENCİ DESTEKLİ AKSİYON TETİKLEYİCİLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _submitLateSlip() async {
    if (_selectedStudents.isEmpty) {
      _warnSelectStudent();
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final targets = List<Map<String, dynamic>>.from(_selectedStudents);
      final created = <StudentMovementRecord>[];
      final notifiedTeachers = <String>{};

      for (final st in targets) {
        final sched = await _resolveScheduleCached(st);
        final slot = _slotForHourFrom(sched.slots, _selectedLessonHour);
        notifiedTeachers.addAll(slot.teacherNames);
        final rec = await _service.issueLateSlip(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          student: st,
          targetSlot: slot,
          reason: _lateReason,
          notes: _lateNotesCtrl.text.trim(),
          markLateInAttendance: _lateAutoAttendance,
        );
        created.add(rec);
      }

      _lateNotesCtrl.clear();
      if (!mounted) return;
      final teacherSummary = notifiedTeachers.isNotEmpty
          ? notifiedTeachers.join(', ')
          : 'ilgili ders öğretmenleri';
      _showBatchSuccessActionSheet(
        created,
        '• ${created.length} öğrenci için $_selectedLessonHour. ders öğretmeni ($teacherSummary) hesabına anlık "Derse kabul / geç kaldı" bildirimi gönderildi.\n'
        '• ${_lateAutoAttendance ? "Her öğrencinin kendi şube yoklama tablosuna otomatik GEÇ işlendi." : "Kayıtlar canlı izleme arşivine eklendi."}',
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitExitPermission() async {
    if (_selectedStudents.isEmpty) {
      _warnSelectStudent();
      return;
    }
    if (_exitReasonCtrl.text.trim().isEmpty) {
      _showError('Lütfen çıkış / izin gerekçesini yazınız.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final targets = List<Map<String, dynamic>>.from(_selectedStudents);
      final created = <StudentMovementRecord>[];
      final typedReceiver = _receiverNameCtrl.text.trim();
      final typedPhone = _receiverPhoneCtrl.text.trim();
      final typedRelation = _receiverRelationCtrl.text.trim();

      for (final st in targets) {
        final sched = await _resolveScheduleCached(st);
        final maxH =
            sched.slots.isNotEmpty ? sched.slots.last.lessonHour : 8;
        final remaining = [
          for (int h = _selectedLessonHour; h <= maxH; h++) h,
        ];
        final slot = _slotForHourFrom(sched.slots, _selectedLessonHour);
        final fallbackParent = _extractParentInfo(st);

        final rec = await _service.issueExitPermission(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          student: st,
          startLessonHour: _selectedLessonHour,
          remainingHours: remaining,
          exitMode: _exitMode,
          reason: _exitReasonCtrl.text.trim(),
          receiverName: typedReceiver.isNotEmpty
              ? typedReceiver
              : fallbackParent.name,
          receiverRelation: typedRelation.isNotEmpty
              ? typedRelation
              : fallbackParent.relation,
          receiverPhone:
              typedPhone.isNotEmpty ? typedPhone : fallbackParent.phone,
          plannedExitTime: _plannedExitTimeCtrl.text.trim(),
          notes: _exitNotesCtrl.text.trim(),
          currentSlot: slot,
        );
        created.add(rec);
      }

      _exitNotesCtrl.clear();
      if (!mounted) return;
      _showBatchSuccessActionSheet(
        created,
        '• Güvenlik birimine ${created.length} öğrenci için "Çıkış yapacak — kapı onayı bekleniyor" bildirimi gönderildi.\n'
        '• Güvenlik kapıdan çıkışı onayladığı anda öğrenciler bugünün kalan derslerinde OTOMATİK İZİNLİ yazılacaktır.',
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _confirmGateExitDialog(StudentMovementRecord record) async {
    final gateNoteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF0284C7),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Güvenlik Kapı Çıkış Onayı',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record.studentName} (${record.className}) öğrencisinin kapıdan çıkış yaptığını onaylıyor musunuz?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Text(
                  'Çıkış Şekli: ${record.exitMode}\n'
                  '${record.receiverName.isNotEmpty ? "Teslim Alan: ${record.receiverName} (${record.receiverRelation})\n" : ""}'
                  'Onaylandığında öğrenci bugünün kalan tüm derslerinde OTOMATİK İZİNLİ yazılacaktır.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0C4A6E),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildPremiumTextField(
                controller: gateNoteCtrl,
                label: 'Güvenlik / Kapı Notu',
                badgeText: 'İsteğe Bağlı',
                hint: 'Örn: Kimlik kontrolü yapıldı, velisine teslim edildi',
                icon: Icons.shield_outlined,
                accentColor: const Color(0xFF0284C7),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text(
              'Çıkış Yaptı — Onayla',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _isSubmitting = true);
    try {
      final excusedHours = await _service.approveGateExit(
        record: record,
        gateNote: gateNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '✓ ${record.studentName} çıkışı onaylandı! ${excusedHours.isNotEmpty ? "${excusedHours.map((h) => "$h.").join(", ")} dersler otomatik İZİNLİ işlendi." : "Kalan dersler izinli işlendi."}',
          ),
        ),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitEarlyPickup() async {
    if (_selectedStudents.isEmpty) {
      _warnSelectStudent();
      return;
    }
    if (_earlyReason.trim().isEmpty) {
      _showError('Lütfen erken alma nedenini seçiniz veya yazınız.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final targets = List<Map<String, dynamic>>.from(_selectedStudents);
      final created = <StudentMovementRecord>[];
      final typedReceiver = _earlyReceiverNameCtrl.text.trim();
      final typedPhone = _earlyReceiverPhoneCtrl.text.trim();

      for (final st in targets) {
        final sched = await _resolveScheduleCached(st);
        final chosenHour =
            _earlyArrivedNow ? sched.currentLessonHour : _selectedLessonHour;
        final maxH =
            sched.slots.isNotEmpty ? sched.slots.last.lessonHour : 8;
        final remaining = [
          for (int h = chosenHour; h <= maxH; h++) h,
        ];
        final slot = _slotForHourFrom(sched.slots, chosenHour);
        final fallbackParent = _extractParentInfo(st);
        final rec = await _service.createEarlyPickupNotice(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          student: st,
          targetLessonHour: chosenHour,
          remainingHours: remaining,
          targetSlot: slot,
          plannedPickupTime: _earlyArrivedNow
              ? DateFormat('HH:mm').format(DateTime.now())
              : _earlyPlannedTimeCtrl.text.trim(),
          receiverName: typedReceiver.isNotEmpty
              ? typedReceiver
              : fallbackParent.name,
          receiverRelation: _earlyRelation,
          receiverPhone:
              typedPhone.isNotEmpty ? typedPhone : fallbackParent.phone,
          vehiclePlate: _earlyPlateCtrl.text.trim(),
          reason: _earlyReason.trim(),
          notes: _earlyNotesCtrl.text.trim(),
          arrivedNow: _earlyArrivedNow,
          requestSource: 'school_admin',
        );
        created.add(rec);
      }

      _earlyNotesCtrl.clear();
      if (!mounted) return;
      _showBatchSuccessActionSheet(
        created,
        _earlyArrivedNow
            ? '• Veli okula geldi olarak kaydedildi; ${created.length} öğrencinin ŞU AN DERSİ OLAN ÖĞRETMENİNE ve GÜVENLİK BİRİMİNE anlık "Öğrenciyi çıkışa hazırlayın" çağrısı gönderildi.\n'
              '• Güvenlik kapıdan teslimi onayladığında kalan dersler otomatik İZİNLİ yazılacaktır.'
            : '• ${created.length} öğrenci için planlı erken alma ön bildirimi kaydedildi; güvenlik ve ilgili ders öğretmeni bilgilendirildi.\n'
              '• Veli okula ulaştığında Veli Panelinden "Okula Geldim" diyebilir veya listeden tek tıkla "Veli Okula Geldi" çağrısı başlatabilirsiniz.',
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _markEarlyParentArrived(StudentMovementRecord record) async {
    setState(() => _isSubmitting = true);
    try {
      await _service.notifyParentArrivedAtSchool(
        record: record,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0D9488),
          content: Text(
            '📍 ${record.studentName} velisi okula geldi! Öğrencinin şu an dersi olan öğretmenine ve güvenliğe anlık hazırlık bildirimi gönderildi.',
          ),
        ),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendStudentToGate(StudentMovementRecord record) async {
    setState(() => _isSubmitting = true);
    try {
      await _service.sendStudentToGateForEarlyPickup(record: record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0284C7),
          content: Text(
            '🎒 ${record.studentName} kapıya yönlendirildi; veliye ve güvenlik birimine bilgi gönderildi.',
          ),
        ),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitInfirmaryReferral() async {
    if (_selectedStudents.isEmpty) {
      _warnSelectStudent();
      return;
    }
    if (_infirmaryComplaintCtrl.text.trim().isEmpty) {
      _showError(
        'Lütfen öğrencinin sağlık şikayetini / sevk nedenini giriniz.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final targets = List<Map<String, dynamic>>.from(_selectedStudents);
      final created = <StudentMovementRecord>[];

      for (final st in targets) {
        final sched = await _resolveScheduleCached(st);
        final slot = _slotForHourFrom(sched.slots, _selectedLessonHour);
        final rec = await _service.issueInfirmaryReferral(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          student: st,
          currentSlot: slot,
          complaint: _infirmaryComplaintCtrl.text.trim(),
          urgency: _infirmaryUrgency,
          notes: _infirmaryNotesCtrl.text.trim(),
        );
        created.add(rec);
      }

      _infirmaryComplaintCtrl.clear();
      _infirmaryNotesCtrl.clear();
      if (!mounted) return;
      _showBatchSuccessActionSheet(
        created,
        '• Sağlık İşlemleri (Revir) ekranında ${created.length} açık sağlık dosyası oluşturuldu.\n'
        '• Revir görevlisi müdahaleyi tamamlayıp kaydettiğinde hem Veliye, hem size, hem de dersi olan öğretmene otomatik sonuç bildirimi gidecektir.',
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showCompleteInfirmaryDialog(
    StudentMovementRecord record,
  ) async {
    final treatmentCtrl = TextEditingController();
    final medNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: record.notes);
    bool medGiven = false;
    String outcome = 'Derse Döndü';
    const accent = Color(0xFFE11D48);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Revir Müdahalesi & Dosya Tamamlama\n${record.studentName} (${record.className})',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECDD3)),
                    ),
                    child: Text(
                      'Sevk Şikayeti: ${record.reason}\nSevk Eden: ${record.createdByName} (${DateFormat("HH:mm").format(record.createdAt)})',
                      style: const TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9F1239),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildPremiumTextField(
                    controller: treatmentCtrl,
                    label: 'Revirde Yapılan İşlem / Müdahale',
                    badgeText: 'Zorunlu',
                    hint:
                        'Örn: Ateş ve tansiyon ölçüldü (36.7°C), soğuk kompres uygulandı, 15 dk dinlendirildi...',
                    icon: Icons.healing_rounded,
                    accentColor: accent,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _buildPremiumSwitchCard(
                    title: 'İlaç / Medikal Uygulama Verildi mi?',
                    subtitle:
                        'Pansuman, buz uygulaması veya veli onaylı medikal destek verildiyse işaretleyin.',
                    value: medGiven,
                    accentColor: accent,
                    icon: Icons.medication_outlined,
                    onChanged: (v) => setModalState(() => medGiven = v),
                  ),
                  if (medGiven) ...[
                    const SizedBox(height: 12),
                    _buildPremiumTextField(
                      controller: medNameCtrl,
                      label: 'Verilen İlaç / Malzeme Adı',
                      hint: 'Örn: Pansuman / Yara bandı / Veli onaylı ilaç',
                      icon: Icons.medical_information_outlined,
                      accentColor: accent,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildVerticalSingleChecklist<String>(
                    label: 'Sonuç / Yönlendirme Kararı',
                    accentColor: accent,
                    selectedValue: outcome,
                    items: const [
                      (
                        value: 'Derse Döndü',
                        title: 'Derse Döndü (Durumu İyi)',
                        subtitle: null,
                        trailingBadge: 'Sınıfa Yönlendir',
                      ),
                      (
                        value: 'İstirahat Sonrası Derse Döndü',
                        title: 'İstirahat Sonrası Derse Döndü',
                        subtitle: null,
                        trailingBadge: 'Dinlendirildi',
                      ),
                      (
                        value: 'Veliye Teslim / Eve Sevk Önerildi',
                        title: 'Veliye Teslim / Eve-Hastaneye Sevk Önerildi',
                        subtitle: null,
                        trailingBadge: 'Veli Bilgilendirilir',
                      ),
                    ],
                    onSelected: (v) => setModalState(() => outcome = v),
                  ),
                  const SizedBox(height: 12),
                  _buildPremiumTextField(
                    controller: notesCtrl,
                    label: 'Ek Revir Notu',
                    badgeText: 'İsteğe Bağlı',
                    hint: 'Veli ve öğretmene iletilecek ek gözlem notu...',
                    icon: Icons.notes_rounded,
                    accentColor: accent,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (treatmentCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Lütfen yapılan müdahaleyi yazınız.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text(
                'Tamamla & Veli / Öğretmene Bildir',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    setState(() => _isSubmitting = true);
    try {
      await _service.completeInfirmaryVisit(
        institutionId: widget.institutionId,
        schoolDocId: record.schoolDocId,
        healthVisitId: record.healthVisitId,
        movementId: record.id,
        treatment: treatmentCtrl.text.trim(),
        medicationGiven: medGiven,
        medicationName: medNameCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        outcome: outcome,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            '✓ ${record.studentName} revir işlemi tamamlandı! Veliye, yönlendirene ve ders öğretmenine bildirim gönderildi.',
          ),
        ),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitInterview() async {
    if (_selectedStudents.isEmpty) {
      _warnSelectStudent();
      return;
    }
    if (_selectedInterviewHours.isEmpty) {
      _showError('Lütfen görüşmenin kapsadığı en az bir ders saati seçiniz.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final targets = List<Map<String, dynamic>>.from(_selectedStudents);
      final sortedHours = _selectedInterviewHours.toList()..sort();
      final created = <StudentMovementRecord>[];
      final notifiedTeachers = <String>{};

      for (final st in targets) {
        final sched = await _resolveScheduleCached(st);
        final studentSlots = sortedHours
            .map((h) => _slotForHourFrom(sched.slots, h))
            .toList();
        for (final sl in studentSlots) {
          notifiedTeachers.addAll(sl.teacherNames);
        }

        final rec = await _service.startStudentInterview(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          student: st,
          coveredSlots: studentSlots,
          interviewUnit: _interviewUnit,
          interviewerName: _interviewerNameCtrl.text.trim(),
          reason: _interviewTopicCtrl.text.trim(),
          notes: _interviewNotesCtrl.text.trim(),
          protectAttendance: _interviewProtectAttendance,
        );
        created.add(rec);
      }

      _interviewNotesCtrl.clear();
      if (!mounted) return;
      final teacherInfo = notifiedTeachers.isNotEmpty
          ? ' (${notifiedTeachers.take(5).join(", ")}${notifiedTeachers.length > 5 ? "..." : ""})'
          : '';
      _showBatchSuccessActionSheet(
        created,
        '• ${created.length} öğrencinin seçilen saatlerdeki ders öğretmenlerine$teacherInfo öğrencilerin görüşmede olduğu ve YOK YAZILMAMASI gerektiği bildirildi.\n'
        '• ${_interviewProtectAttendance ? "Seçilen ders saatlerinde (${sortedHours.map((h) => "$h.").join(", ")} ders) yoklama tablolarına otomatik İZİNLİ koruması işlendi." : "Canlı izleme ekranında görüşmede olarak işaretlendi."}',
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _warnSelectStudent() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lütfen önce listeden en az bir öğrenci seçiniz.'),
        backgroundColor: Color(0xFFD97706),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PREMİUM FORM & GİRDİ BİLEŞENLERİ (EXECUTIVE DESIGN SYSTEM)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPremiumSectionCard({
    required String stepBadge,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    Widget? headerTrailing,
    required List<Widget> children,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accentColor,
                          accentColor.withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                stepBadge,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (headerTrailing != null) headerTrailing,
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildFieldLabel(
    String label, {
    String? badgeText,
    Color? accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (badgeText != null && badgeText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: badgeText == 'Zorunlu'
                    ? (accentColor ?? const Color(0xFF6366F1))
                        .withValues(alpha: 0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: badgeText == 'Zorunlu'
                      ? (accentColor ?? const Color(0xFF6366F1))
                      : const Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrefixIconBadge(IconData icon, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 8),
      child: Center(
        widthFactor: 1,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16.5, color: accentColor),
        ),
      ),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color accentColor,
    String? hint,
    String? badgeText,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, badgeText: badgeText, accentColor: accentColor),
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          textAlignVertical:
              maxLines == 1 ? TextAlignVertical.center : TextAlignVertical.top,
          onChanged: onChanged,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 14 : 13,
            ),
            prefixIcon: maxLines == 1
                ? _buildPrefixIconBadge(icon, accentColor)
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 44,
            ),
            suffixIcon: suffix,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: accentColor, width: 1.8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required IconData icon,
    required Color accentColor,
    String? badgeText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, badgeText: badgeText, accentColor: accentColor),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.grey.shade600,
            size: 22,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            prefixIcon: _buildPrefixIconBadge(icon, accentColor),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 44,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: accentColor, width: 1.8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildChecklistRowItem({
    required bool isSelected,
    required String title,
    String? subtitle,
    String? trailingBadge,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBadge =
            trailingBadge != null && trailingBadge.trim().isNotEmpty;
        final stackBadgeBelow =
            hasBadge &&
            constraints.maxWidth < 460 &&
            trailingBadge.trim().length > 14;

        Widget buildBadge({double maxWidth = 260}) {
          return Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.14)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              trailingBadge!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.2,
                fontWeight: FontWeight.w700,
                color: isSelected ? accentColor : const Color(0xFF475569),
              ),
            ),
          );
        }

        return Material(
          color: isSelected
              ? accentColor.withValues(alpha: 0.065)
              : Colors.white,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10.5,
              ),
              child: Row(
                crossAxisAlignment: stackBadgeBelow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: stackBadgeBelow ? 2 : 0),
                    child: Icon(
                      isSelected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: isSelected ? accentColor : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected
                                ? accentColor
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 11.3,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                        if (stackBadgeBelow) ...[
                          const SizedBox(height: 5),
                          buildBadge(maxWidth: constraints.maxWidth - 48),
                        ],
                      ],
                    ),
                  ),
                  if (hasBadge && !stackBadgeBelow) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 0,
                      child: buildBadge(
                        maxWidth: constraints.maxWidth < 460 ? 140 : 260,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVerticalSingleChecklist<T>({
    required String label,
    String? badgeText,
    Widget? headerTrailing,
    required Color accentColor,
    required List<({
      T value,
      String title,
      String? subtitle,
      String? trailingBadge,
    })> items,
    required T? selectedValue,
    required ValueChanged<T> onSelected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader =
            headerTrailing != null && constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stackHeader) ...[
              _buildFieldLabel(
                label,
                badgeText: badgeText,
                accentColor: accentColor,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: headerTrailing,
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _buildFieldLabel(
                      label,
                      badgeText: badgeText,
                      accentColor: accentColor,
                    ),
                  ),
                  if (headerTrailing != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: headerTrailing,
                    ),
                ],
              ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F5F9),
                      ),
                    _buildChecklistRowItem(
                      isSelected: selectedValue == items[i].value,
                      title: items[i].title,
                      subtitle: items[i].subtitle,
                      trailingBadge: items[i].trailingBadge,
                      accentColor: accentColor,
                      onTap: () => onSelected(items[i].value),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVerticalMultiChecklist<T>({
    required String label,
    String? badgeText,
    Widget? headerTrailing,
    required Color accentColor,
    required List<({
      T value,
      String title,
      String? subtitle,
      String? trailingBadge,
    })> items,
    required Set<T> selectedValues,
    required void Function(T value, bool nextSelected) onToggle,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackHeader =
            headerTrailing != null && constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stackHeader) ...[
              _buildFieldLabel(
                label,
                badgeText: badgeText,
                accentColor: accentColor,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: headerTrailing,
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _buildFieldLabel(
                      label,
                      badgeText: badgeText,
                      accentColor: accentColor,
                    ),
                  ),
                  if (headerTrailing != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: headerTrailing,
                    ),
                ],
              ),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F5F9),
                      ),
                    _buildChecklistRowItem(
                      isSelected: selectedValues.contains(items[i].value),
                      title: items[i].title,
                      subtitle: items[i].subtitle,
                      trailingBadge: items[i].trailingBadge,
                      accentColor: accentColor,
                      onTap: () {
                        final cur = selectedValues.contains(items[i].value);
                        onToggle(items[i].value, !cur);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPremiumSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required Color accentColor,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? accentColor.withValues(alpha: 0.055)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? accentColor.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? accentColor.withValues(alpha: 0.14)
                    : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 19,
                color: value ? accentColor : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13.2,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.6,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: accentColor,
              activeTrackColor: accentColor.withValues(alpha: 0.35),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumSubmitButton({
    required String baseLabel,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    final selCount = _selectedStudents.length;
    final countSuffix = selCount > 1 ? ' ($selCount ÖĞRENCİ)' : '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            accentColor,
            Color.lerp(accentColor, const Color(0xFF0F172A), 0.16)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 20, color: Colors.white),
        label: Text(
          '$baseLabel$countSuffix',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            letterSpacing: 0.3,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANA EKRAN İSKELETİ
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }

    final todayStr = StudentMovementService.formatDateYmd(DateTime.now());

    return StreamBuilder<List<StudentMovementRecord>>(
      stream: _service.watchMovementsForDate(
        schoolDocId: _schoolDocId,
        dateStr: todayStr,
        schoolTypeId: widget.schoolTypeId,
      ),
      builder: (context, todaySnap) {
        final todayRecords = todaySnap.data ?? const <StudentMovementRecord>[];

        if (widget.isSecurityPortalMode) {
          return _buildSecurityGateOnlyView(todayRecords);
        }

        final activeOutCount =
            todayRecords.where((r) => r.isActivelyOutOfClass).length;
        final pendingGateCount = todayRecords
            .where(
              (r) =>
                  r.status == StudentMovementStatus.pendingGate ||
                  r.status == StudentMovementStatus.parentArrived,
            )
            .length;
        final earlyPickupCount = todayRecords
            .where(
              (r) =>
                  r.status == StudentMovementStatus.earlyPickupNotified ||
                  r.status == StudentMovementStatus.parentArrived ||
                  (r.type == StudentMovementType.earlyPickup &&
                      r.status == StudentMovementStatus.pendingGate),
            )
            .length;
        final openInfirmaryCount = todayRecords
            .where((r) => r.status == StudentMovementStatus.inInfirmary)
            .length;
        final activeMeetingCount = todayRecords
            .where((r) => r.status == StudentMovementStatus.inMeeting)
            .length;

        return Column(
          children: [
            _buildTopModeBar(
              activeOutCount: activeOutCount,
              pendingGateCount: pendingGateCount,
              earlyPickupCount: earlyPickupCount,
              openInfirmaryCount: openInfirmaryCount,
              activeMeetingCount: activeMeetingCount,
            ),
            Expanded(
              child: IndexedStack(
                index: _activeTab,
                children: [
                  _buildLiveMonitorTab(todayRecords),
                  _buildLateSlipTab(todayRecords),
                  _buildExitPermissionTab(todayRecords),
                  _buildEarlyPickupTab(todayRecords),
                  _buildInfirmaryTab(todayRecords),
                  _buildInterviewTab(todayRecords),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GÜVENLİK BİRİMİ ÖZEL EKRANI (SADECE KAPI ÇIKIŞ ONAYI)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSecurityGateOnlyView(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFF0284C7);
    final now = DateTime.now();
    final liveDateTimeStr =
        '${DateFormat("dd.MM.yyyy").format(now)} ${StudentMovementService.dayNameTr(now.weekday)} • Saat ${DateFormat("HH:mm").format(now)}';

    final q = _normTr(_securitySearchQuery);
    bool matchesSearch(StudentMovementRecord r) {
      if (q.isEmpty) return true;
      final hay = _normTr(
        '${r.studentName} ${r.className} ${r.studentNo} ${r.receiverName} ${r.vehiclePlate}',
      );
      return hay.contains(q);
    }

    final pendingList = todayRecords
        .where(
          (r) =>
              (r.status == StudentMovementStatus.pendingGate ||
                  r.status == StudentMovementStatus.parentArrived ||
                  r.status == StudentMovementStatus.earlyPickupNotified) &&
              matchesSearch(r),
        )
        .toList();

    final approvedList = todayRecords
        .where(
          (r) =>
              r.status == StudentMovementStatus.exitedSchool &&
              matchesSearch(r),
        )
        .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
          children: [
            // Üst Durum & Canlı Saat Başlığı + Hızlı Arama
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.shield_rounded,
                              color: accent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Güvenlik Kapı Çıkış Onay Ekranı',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'İzin verilen öğrencilerin kapıdan çıkışını tek tıkla onaylayın',
                                style: GoogleFonts.inter(
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time_filled_rounded,
                                  size: 15,
                                  color: Color(0xFF0F172A),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  liveDateTimeStr,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: pendingList.isNotEmpty
                                  ? const Color(0xFFFFF7ED)
                                  : const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: pendingList.isNotEmpty
                                    ? const Color(0xFFFB923C)
                                    : const Color(0xFFBAE6FD),
                              ),
                            ),
                            child: Text(
                              'Bekleyen Çıkış: ${pendingList.length}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: pendingList.isNotEmpty
                                    ? const Color(0xFFEA580C)
                                    : const Color(0xFF0369A1),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: Text(
                              'Bugün Çıkan: ${approvedList.length}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildPremiumTextField(
                    controller: _securitySearchCtrl,
                    label: 'Kapı Kontrol Hızlı Arama',
                    hint:
                        'Öğrenci adı, okul no, şube, teslim alacak veli veya plaka ara...',
                    icon: Icons.search_rounded,
                    accentColor: accent,
                    onChanged: (v) => setState(() => _securitySearchQuery = v),
                    suffix: _securitySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _securitySearchCtrl.clear();
                              setState(() => _securitySearchQuery = '');
                            },
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 1. ÇIKIŞ ONAYI BEKLEYEN ÖĞRENCİLER
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: pendingList.isNotEmpty
                    ? const Color(0xFFFFF7ED)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: pendingList.isNotEmpty
                      ? const Color(0xFFFB923C)
                      : const Color(0xFFE2E8F0),
                  width: pendingList.isNotEmpty ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sensor_door_rounded,
                        color: pendingList.isNotEmpty
                            ? const Color(0xFFEA580C)
                            : accent,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Çıkış Onayı Bekleyen Öğrenciler (${pendingList.length})',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pendingList.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 36,
                            color: Colors.blueGrey.shade300,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Şu an kapı çıkış onayı bekleyen öğrenci bulunmuyor.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'İdare tarafından öğrenciye çıkış izni verildiğinde anlık olarak bu listeye düşer.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: pendingList
                          .map(_buildSecurityPendingCard)
                          .toList(),
                    ),
                ],
              ),
            ),

            // 2. BUGÜN ÇIKIŞI ONAYLANAN ÖĞRENCİLER (SALT OKUNUR KAPI KAYDI)
            if (approvedList.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Bugün Kapıdan Çıkışı Onaylanan Öğrenciler (${approvedList.length})',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...approvedList.map(_buildSecurityApprovedTile),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityPendingCard(StudentMovementRecord r) {
    final issueTime = DateFormat('HH:mm').format(r.createdAt);
    final isEarly = r.type == StudentMovementType.earlyPickup;
    final badgeColor = isEarly
        ? const Color(0xFF0D9488)
        : const Color(0xFF0284C7);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${r.studentName} • Şube: ${r.className}${r.studentNo.isNotEmpty ? " (No: ${r.studentNo})" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isEarly ? 'Veli Erken Alma' : r.exitMode,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'İzin Saati: $issueTime${r.plannedExitTime.isNotEmpty ? " • Planlanan: ${r.plannedExitTime}" : ""}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (r.receiverName.isNotEmpty || r.vehiclePlate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '👤 Teslim Alacak: ${r.receiverName.isNotEmpty ? r.receiverName : "Veli"}'
                      '${r.receiverRelation.isNotEmpty ? " (${r.receiverRelation})" : ""}'
                      '${r.receiverPhone.isNotEmpty ? " • Tel: ${r.receiverPhone}" : ""}'
                      '${r.vehiclePlate.isNotEmpty ? " • Plaka: ${r.vehiclePlate}" : ""}',
                      style: GoogleFonts.inter(
                        fontSize: 12.4,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                Text(
                  '📋 Ders: ${r.lessonHour}. Ders${r.lessonTimeRangeLabel.isNotEmpty ? " (${r.lessonTimeRangeLabel})" : ""}'
                  '${r.reason.isNotEmpty ? " • Neden: ${r.reason}" : ""}'
                  '${r.notes.isNotEmpty ? " • Not: ${r.notes}" : ""}'
                  ' • Onaylayan İdare: ${r.createdByName}',
                  style: GoogleFonts.inter(
                    fontSize: 11.6,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : () => _confirmGateExitDialog(r),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.verified_user_rounded, size: 19),
            label: Text(
              'ÇIKIŞ ONAYI VER',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityApprovedTile(StudentMovementRecord r) {
    final exitTime = r.gateApprovedAt != null
        ? DateFormat('HH:mm').format(r.gateApprovedAt!)
        : DateFormat('HH:mm').format(r.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              children: [
                Text(
                  exitTime,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                    color: const Color(0xFF059669),
                  ),
                ),
                Text(
                  'ÇIKTI',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.studentName} • Şube: ${r.className}${r.studentNo.isNotEmpty ? " (No: ${r.studentNo})" : ""}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.2,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.exitMode}'
                  '${r.receiverName.isNotEmpty ? " • Teslim Alan: ${r.receiverName}" : ""}'
                  '${r.gateApprovedByName.isNotEmpty ? " • Güvenlik Onayı: ${r.gateApprovedByName}" : ""}'
                  '${r.gateNote.isNotEmpty ? " • Kapı Notu: ${r.gateNote}" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopModeBar({
    required int activeOutCount,
    required int pendingGateCount,
    required int earlyPickupCount,
    required int openInfirmaryCount,
    required int activeMeetingCount,
  }) {
    final tabs = <({
      int idx,
      String title,
      IconData icon,
      Color color,
      int badge,
    })>[
      (
        idx: 0,
        title: 'CANLI İZLEME',
        icon: Icons.radar_rounded,
        color: const Color(0xFF0F172A),
        badge: activeOutCount,
      ),
      (
        idx: 1,
        title: 'GEÇ KAĞIDI',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFD97706),
        badge: 0,
      ),
      (
        idx: 2,
        title: 'İZİN & GÜVENLİK',
        icon: Icons.sensor_door_rounded,
        color: const Color(0xFF0284C7),
        badge: pendingGateCount,
      ),
      (
        idx: 3,
        title: 'ERKEN ALMA',
        icon: Icons.directions_car_filled_rounded,
        color: const Color(0xFF0D9488),
        badge: earlyPickupCount,
      ),
      (
        idx: 4,
        title: 'REVİR SEVK',
        icon: Icons.local_hospital_rounded,
        color: const Color(0xFFE11D48),
        badge: openInfirmaryCount,
      ),
      (
        idx: 5,
        title: 'GÖRÜŞME',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF7C3AED),
        badge: activeMeetingCount,
      ),
    ];

    final now = DateTime.now();
    final liveDateText =
        '${DateFormat("dd.MM.yyyy").format(now)} ${StudentMovementService.dayNameTr(now.weekday)}';
    final liveClockText = DateFormat('HH:mm').format(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactMobile = constraints.maxWidth < 720;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompactMobile ? 10 : 18,
            vertical: isCompactMobile ? 8 : 11,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tabs.map((t) {
                      final selected = _activeTab == t.idx;
                      return Padding(
                        padding: EdgeInsets.only(right: isCompactMobile ? 6 : 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _activeTab = t.idx),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompactMobile ? 12 : 15,
                              vertical: isCompactMobile ? 8.5 : 9.5,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? t.color
                                  : t.color.withValues(alpha: 0.065),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? t.color
                                    : t.color.withValues(alpha: 0.20),
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: t.color.withValues(alpha: 0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  t.icon,
                                  size: isCompactMobile ? 16 : 17,
                                  color: selected ? Colors.white : t.color,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  t.title,
                                  style: GoogleFonts.inter(
                                    fontSize: isCompactMobile ? 11.8 : 12.3,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? Colors.white : t.color,
                                  ),
                                ),
                                if (t.badge > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6.5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected ? Colors.white : t.color,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${t.badge}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color:
                                            selected ? t.color : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (!isCompactMobile) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_filled_rounded,
                        size: 15,
                        color: Color(0xFF0F172A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$liveDateText • $liveClockText',
                        style: GoogleFonts.inter(
                          fontSize: 11.6,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 0: CANLI İZLEME EKRANI ("KİM NEREDE?")
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveMonitorTab(List<StudentMovementRecord> todayLiveRecords) {
    final isToday = StudentMovementService.formatDateYmd(_monitorDate) ==
        StudentMovementService.formatDateYmd(DateTime.now());

    if (!isToday) {
      return StreamBuilder<List<StudentMovementRecord>>(
        stream: _service.watchMovementsForDate(
          schoolDocId: _schoolDocId,
          dateStr: StudentMovementService.formatDateYmd(_monitorDate),
          schoolTypeId: widget.schoolTypeId,
        ),
        builder: (context, snap) =>
            _buildMonitorContent(snap.data ?? const [], isToday: false),
      );
    }

    return _buildMonitorContent(todayLiveRecords, isToday: true);
  }

  Widget _buildMonitorContent(
    List<StudentMovementRecord> allRecords, {
    required bool isToday,
  }) {
    final parentArrivedList = allRecords
        .where((r) => r.status == StudentMovementStatus.parentArrived)
        .toList();
    final plannedEarlyList = allRecords
        .where((r) => r.status == StudentMovementStatus.earlyPickupNotified)
        .toList();
    final inInfirmary = allRecords
        .where((r) => r.status == StudentMovementStatus.inInfirmary)
        .toList();
    final inMeeting = allRecords
        .where((r) => r.status == StudentMovementStatus.inMeeting)
        .toList();
    final pendingGate = allRecords
        .where((r) => r.status == StudentMovementStatus.pendingGate)
        .toList();
    final exited = allRecords
        .where((r) => r.status == StudentMovementStatus.exitedSchool)
        .toList();
    final lateToday = allRecords
        .where((r) => r.type == StudentMovementType.lateSlip)
        .toList();

    final activeRadarList = [
      ...parentArrivedList,
      ...pendingGate,
      ...inInfirmary,
      ...inMeeting,
      ...exited,
    ];

    final filteredLog = allRecords.where((r) {
      if (_monitorTypeFilter != null && r.type != _monitorTypeFilter) {
        return false;
      }
      if (_monitorClassFilter.isNotEmpty &&
          r.className != _monitorClassFilter) {
        return false;
      }
      if (_monitorSearch.trim().isNotEmpty) {
        final q = _normTr(_monitorSearch);
        final hay = _normTr(
          '${r.studentName} ${r.studentNo} ${r.className} ${r.reason} ${r.liveLocationDescription}',
        );
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKpiCard(
              title: 'Erken Alma / Kapıda',
              count: parentArrivedList.length + plannedEarlyList.length,
              subtitle: parentArrivedList.isNotEmpty
                  ? '${parentArrivedList.length} veli kapıda bekliyor!'
                  : 'Planlı & kapı çağrı',
              icon: Icons.directions_car_filled_rounded,
              color: const Color(0xFF0D9488),
              onTap: () => setState(() => _activeTab = 3),
            ),
            _buildKpiCard(
              title: 'Şu An Revirde',
              count: inInfirmary.length,
              subtitle: 'Açık sağlık dosyası',
              icon: Icons.local_hospital_rounded,
              color: const Color(0xFFE11D48),
              onTap: () => setState(() => _activeTab = 4),
            ),
            _buildKpiCard(
              title: 'Şu An Görüşmede',
              count: inMeeting.length,
              subtitle: 'Rehberlik / İdare',
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFF7C3AED),
              onTap: () => setState(() => _activeTab = 5),
            ),
            _buildKpiCard(
              title: 'Kapı Onayı Bekleyen',
              count: pendingGate.length + parentArrivedList.length,
              subtitle: 'Güvenlik çıkışı bekliyor',
              icon: Icons.sensor_door_rounded,
              color: const Color(0xFFEA580C),
              onTap: () => setState(() => _activeTab = 2),
            ),
            _buildKpiCard(
              title: 'Okuldan Çıkış Yapan',
              count: exited.length,
              subtitle: 'Güvenlik onaylı izinli',
              icon: Icons.verified_user_rounded,
              color: const Color(0xFF0284C7),
              onTap: () => setState(
                () => _monitorTypeFilter = StudentMovementType.exitPermission,
              ),
            ),
            _buildKpiCard(
              title: 'Geç Kağıdı Alanlar',
              count: lateToday.length,
              subtitle: 'Derse kabul edilen',
              icon: Icons.schedule_rounded,
              color: const Color(0xFFD97706),
              onTap: () => setState(
                () => _monitorTypeFilter = StudentMovementType.lateSlip,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (isToday && plannedEarlyList.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF5EEAD4), width: 1.3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      color: Color(0xFF0D9488),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '📅 BUGÜN VELİ TARAFINDAN ÖNCEDEN BİLDİRİLEN ERKEN ALMALAR (${plannedEarlyList.length})',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...plannedEarlyList.map(_buildActiveRadarRow),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        if (isToday) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFCBD5E1)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: activeRadarList.isEmpty
                            ? const Color(0xFF10B981)
                            : const Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ANLIK RADAR — ŞU AN SINIF DIŞINDA KİM NEREDE? (${activeRadarList.length} Öğrenci)',
                        style: GoogleFonts.inter(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (activeRadarList.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 22,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF16A34A),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Şu an revirde, görüşmede veya çıkış bekleyen öğrenci bulunmuyor; tüm öğrenciler sınıflarında.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: activeRadarList.map(_buildActiveRadarRow).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Günlük Hareket Arşivi
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.history_edu_rounded,
                          color: Color(0xFF1E293B),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Günlük Öğrenci Hareket Kayıtları (${filteredLog.length})',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _monitorDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => _monitorDate = picked);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        icon: const Icon(
                          Icons.calendar_today_rounded,
                          size: 15,
                        ),
                        label: Text(
                          DateFormat('dd.MM.yyyy').format(_monitorDate),
                        ),
                      ),
                      if (!isToday)
                        TextButton(
                          onPressed: () =>
                              setState(() => _monitorDate = DateTime.now()),
                          child: const Text('Bugüne Dön'),
                        ),
                      ElevatedButton.icon(
                        onPressed: filteredLog.isEmpty
                            ? null
                            : () => _printDailyReport(filteredLog),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        icon: const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 16,
                        ),
                        label: const Text('Günlük Rapor PDF'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 680;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide)
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildPremiumTextField(
                                controller: _monitorSearchCtrl,
                                label: 'Hızlı Arama',
                                hint:
                                    'Öğrenci adı, numara, şube veya açıklama ara...',
                                icon: Icons.search_rounded,
                                accentColor: const Color(0xFF334155),
                                onChanged: (v) =>
                                    setState(() => _monitorSearch = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _buildPremiumDropdown<String>(
                                label: 'Şube Filtresi',
                                value: _monitorClassFilter,
                                icon: Icons.class_outlined,
                                accentColor: const Color(0xFF334155),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Tüm Şubeler'),
                                  ),
                                  ..._classes.map((cl) {
                                    final cn =
                                        (cl['className'] ?? '').toString();
                                    return DropdownMenuItem(
                                      value: cn,
                                      child: Text(cn),
                                    );
                                  }),
                                ],
                                onChanged: (v) => setState(
                                  () => _monitorClassFilter = v ?? '',
                                ),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildPremiumTextField(
                          controller: _monitorSearchCtrl,
                          label: 'Hızlı Arama',
                          hint: 'Öğrenci adı, numara veya şube ara...',
                          icon: Icons.search_rounded,
                          accentColor: const Color(0xFF334155),
                          onChanged: (v) => setState(() => _monitorSearch = v),
                        ),
                        const SizedBox(height: 10),
                        _buildPremiumDropdown<String>(
                          label: 'Şube Filtresi',
                          value: _monitorClassFilter,
                          icon: Icons.class_outlined,
                          accentColor: const Color(0xFF334155),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Tüm Şubeler'),
                            ),
                            ..._classes.map((cl) {
                              final cn = (cl['className'] ?? '').toString();
                              return DropdownMenuItem(
                                value: cn,
                                child: Text(cn),
                              );
                            }),
                          ],
                          onChanged: (v) =>
                              setState(() => _monitorClassFilter = v ?? ''),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPremiumPresetPill(
                            label: 'Tümü',
                            selected: _monitorTypeFilter == null,
                            accentColor: const Color(0xFF0F172A),
                            onTap: () =>
                                setState(() => _monitorTypeFilter = null),
                          ),
                          for (final t in StudentMovementType.values)
                            _buildPremiumPresetPill(
                              label: t.shortLabel,
                              selected: _monitorTypeFilter == t,
                              accentColor: t.color,
                              onTap: () => setState(
                                () => _monitorTypeFilter =
                                    _monitorTypeFilter == t ? null : t,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (filteredLog.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Seçilen kriterlere uygun öğrenci hareket kaydı bulunmuyor.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                Column(
                  children:
                      filteredLog.map(_buildTimelineRecordTile).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumPresetPill({
    required String label,
    required bool selected,
    required Color accentColor,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8.5),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? accentColor : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1.1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected || icon != null) ...[
              Icon(
                selected ? Icons.check_circle_rounded : icon,
                size: 15,
                color: selected ? accentColor : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? accentColor : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
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

  Widget _buildActiveRadarRow(StudentMovementRecord r) {
    final statusColor = r.status.color;
    final startStr = DateFormat('HH:mm').format(r.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: statusColor.withValues(alpha: 0.15),
                child: Icon(r.type.icon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${r.studentName} (${r.className}${r.studentNo.isNotEmpty ? " • No: ${r.studentNo}" : ""})',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            r.status == StudentMovementStatus.exitedSchool
                                ? 'İşlem: $startStr • Çıkış: ${r.gateApprovedAt != null ? DateFormat("HH:mm").format(r.gateApprovedAt!) : startStr}'
                                : 'İşlem: $startStr • ${r.elapsedMinutes} dk',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '📍 Nerede: ${r.liveLocationDescription}',
                      style: GoogleFonts.inter(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    Text(
                      'Ders: ${r.lessonHour}. Ders${r.lessonTimeRangeLabel.isNotEmpty ? " (${r.lessonTimeRangeLabel})" : ""}'
                      '${r.lessonName.isNotEmpty && r.lessonName != "${r.lessonHour}. Ders" ? " • ${r.lessonName}" : ""}'
                      '${r.targetTeacherNames.isNotEmpty ? " • Öğrt: ${r.targetTeacherNames.join(", ")}" : ""}'
                      ' • İşlemi Açan: ${r.createdByName}',
                      style: GoogleFonts.inter(
                        fontSize: 11.3,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (r.status == StudentMovementStatus.earlyPickupNotified)
                ElevatedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _markEarlyParentArrived(r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.where_to_vote_rounded, size: 16),
                  label: const Text('📍 Veli Okula Geldi (Öğretmene Bildir)'),
                ),
              if (r.status == StudentMovementStatus.parentArrived) ...[
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : () => _sendStudentToGate(r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.directions_walk_rounded, size: 16),
                  label: const Text('🎒 Kapıya Yönlendir'),
                ),
                ElevatedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _confirmGateExitDialog(r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.verified_user_rounded, size: 16),
                  label: const Text('Güvenlik Teslim Onayla'),
                ),
              ],
              if (r.status == StudentMovementStatus.pendingGate)
                ElevatedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _confirmGateExitDialog(r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.verified_user_rounded, size: 16),
                  label: const Text('Güvenlik Çıkış Onayla'),
                ),
              if (r.status == StudentMovementStatus.inInfirmary)
                ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _showCompleteInfirmaryDialog(r),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.medical_services_rounded, size: 16),
                  label: const Text('Revir İşlemi Tamamla'),
                ),
              if (r.status == StudentMovementStatus.inMeeting)
                ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await _service.completeStudentInterview(r);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF059669),
                              content: Text(
                                '✓ ${r.studentName} görüşmesi tamamlandı, ders öğretmenine bildirildi.',
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                  ),
                  label: const Text('Görüşmeyi Bitir'),
                ),
              OutlinedButton.icon(
                onPressed: () => _printSlip(r),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.print_rounded, size: 15),
                label: const Text('Pusula'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRecordTile(StudentMovementRecord r) {
    final c = r.type.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('HH:mm').format(r.createdAt),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: c,
                  ),
                ),
                Text(
                  r.type.shortLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    color: c,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${r.studentName} • ${r.className}${r.studentNo.isNotEmpty ? " (No: ${r.studentNo})" : ""}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: r.status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        r.status.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: r.status.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.liveLocationDescription}'
                  '${r.reason.isNotEmpty ? " • Neden: ${r.reason}" : ""}'
                  '${r.infirmaryTreatment.isNotEmpty ? " • Müdahale: ${r.infirmaryTreatment}" : ""}'
                  '${r.autoExcusedHours.isNotEmpty ? " • Otomatik İzinli: ${r.autoExcusedHours.map((h) => "$h.").join(",")} ders" : ""}',
                  style: const TextStyle(
                    fontSize: 11.8,
                    color: Color(0xFF334155),
                  ),
                ),
                Text(
                  '🕒 İşlem Saati: ${DateFormat("HH:mm").format(r.createdAt)}'
                  ' • ${r.lessonHour}. Ders${r.lessonTimeRangeLabel.isNotEmpty ? " (${r.lessonTimeRangeLabel})" : ""}'
                  '${r.lessonName.isNotEmpty && r.lessonName != "${r.lessonHour}. Ders" ? " — ${r.lessonName}" : ""}'
                  '${r.targetTeacherNames.isNotEmpty ? " (${r.targetTeacherNames.join(", ")})" : ""}'
                  ' • Kayıt: ${r.createdByName}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pusula Yazdır',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            onPressed: () => _printSlip(r),
            icon: const Icon(Icons.print_outlined, size: 19),
          ),
          if (r.status != StudentMovementStatus.cancelled &&
              r.status != StudentMovementStatus.completed &&
              r.status != StudentMovementStatus.exitedSchool)
            IconButton(
              tooltip: 'Kaydı İptal Et',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: () => _service.cancelMovement(r),
              icon: Icon(
                Icons.cancel_outlined,
                size: 19,
                color: Colors.red.shade400,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORTAK PREMİUM ÇOKLU ÖĞRENCİ SEÇİCİ PANELİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudentSelectorPanel({required Color accentColor}) {
    final filteredStudents = _students.where((s) {
      if (_selectedClassId.isNotEmpty &&
          (s['classId'] ?? '').toString() != _selectedClassId) {
        return false;
      }
      if (_studentSearchQuery.trim().isNotEmpty) {
        final q = _normTr(_studentSearchQuery);
        final hay = _normTr(
          '${_studentDisplayName(s)} ${_studentNo(s)} ${s['className'] ?? ''}',
        );
        if (!hay.contains(q)) return false;
      }
      return true;
    }).take(80).toList();

    final selCount = _selectedStudents.length;

    return _buildPremiumSectionCard(
      stepBadge: 'ADIM 1 • ÇOKLU SEÇİM DESTEKLİ',
      title: 'Öğrenci Seçimi',
      subtitle:
          'Aynı veya farklı şubelerden tek ya da birden fazla öğrenci seçebilirsiniz',
      icon: Icons.group_add_rounded,
      accentColor: accentColor,
      headerTrailing: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (selCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$selCount Öğrenci Seçili',
                style: GoogleFonts.inter(
                  fontSize: 11.8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (filteredStudents.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _selectVisibleStudents(filteredStudents),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 15),
              label: const Text(
                'Listelenenleri Seç',
                style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700),
              ),
            ),
          if (selCount > 0)
            TextButton.icon(
              onPressed: _clearSelectedStudents,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text(
                'Temizle',
                style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 620;
            final classDropdown = _buildPremiumDropdown<String>(
              label: 'Şube Filtresi',
              value: _classes.any((c) => c['id'] == _selectedClassId)
                  ? _selectedClassId
                  : '',
              icon: Icons.meeting_room_outlined,
              accentColor: accentColor,
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Tüm Şubeler'),
                ),
                ..._classes.map(
                  (c) => DropdownMenuItem(
                    value: (c['id'] ?? '').toString(),
                    child: Text((c['className'] ?? '').toString()),
                  ),
                ),
              ],
              onChanged: (v) => _onClassFilterChanged(v ?? ''),
            );

            final searchField = _buildPremiumTextField(
              controller: _studentSearchCtrl,
              label: 'Öğrenci Adı veya Okul Numarası Ara',
              hint: 'İsim, soyisim veya numara yazarak filtreleyin...',
              icon: Icons.search_rounded,
              accentColor: accentColor,
              onChanged: (v) => setState(() => _studentSearchQuery = v),
              suffix: _studentSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      onPressed: () {
                        _studentSearchCtrl.clear();
                        setState(() => _studentSearchQuery = '');
                      },
                    )
                  : null,
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: classDropdown),
                  const SizedBox(width: 14),
                  Expanded(flex: 3, child: searchField),
                ],
              );
            }
            return Column(
              children: [
                classDropdown,
                const SizedBox(height: 12),
                searchField,
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // Öğrenci Seçim Listesi (Alt Alta Çeklist)
        Container(
          constraints: const BoxConstraints(maxHeight: 265),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: filteredStudents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Arama kriterine uygun öğrenci bulunamadı.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: filteredStudents.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                  itemBuilder: (_, idx) => _buildStudentSelectableTile(
                    filteredStudents[idx],
                    accentColor,
                  ),
                ),
        ),

        // Seçili Öğrenciler Listesi (Alt Alta Seçili Çeklist)
        if (_selectedStudents.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: accentColor,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          selCount == 1
                              ? 'Seçili Öğrenci'
                              : 'İşlem Yapılacak Seçili Öğrenciler ($selCount Kişi)',
                          style: GoogleFonts.inter(
                            fontSize: 12.4,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (_hasMultiClassSelection)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${_selectedDistinctClassNames.length} Farklı Şube',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE2E8F0),
                ),
                for (int i = 0; i < _selectedStudents.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFF1F5F9),
                    ),
                  Builder(
                    builder: (_) {
                      final st = _selectedStudents[i];
                      final sid = (st['id'] ?? '').toString();
                      final counts = _studentCountsCache[sid];
                      final cls = (st['className'] ?? '').toString();
                      final no = _studentNo(st);
                      return Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_box_rounded,
                              size: 19,
                              color: accentColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_studentDisplayName(st)}${no.isNotEmpty ? " (No: $no)" : ""}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.6,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (counts != null)
                                    Text(
                                      'Geç: ${counts[StudentMovementType.lateSlip] ?? 0} • İzin: ${counts[StudentMovementType.exitPermission] ?? 0} • Erken: ${counts[StudentMovementType.earlyPickup] ?? 0} • Revir: ${counts[StudentMovementType.infirmary] ?? 0} • Görüşme: ${counts[StudentMovementType.interview] ?? 0}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3.5,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cls.isNotEmpty ? 'Şube: $cls' : 'Şubesiz',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _toggleStudentSelection(st),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 17,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStudentSelectableTile(
    Map<String, dynamic> st,
    Color accentColor,
  ) {
    final isSel = _isStudentSelected(st);
    final stName = _studentDisplayName(st);
    final stNo = _studentNo(st);
    final clsName = (st['className'] ?? '').toString();

    return Material(
      color: isSel ? accentColor.withValues(alpha: 0.065) : Colors.white,
      child: InkWell(
        onTap: () => _toggleStudentSelection(st),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              Icon(
                isSel
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: isSel ? accentColor : const Color(0xFFCBD5E1),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                    color: isSel ? accentColor : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSel
                      ? accentColor.withValues(alpha: 0.14)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Şube: $clsName${stNo.isNotEmpty ? " • No: $stNo" : ""}',
                  style: GoogleFonts.inter(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
                    color: isSel ? accentColor : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveOperationAndScheduleHeader({
    required Color accentColor,
    required List<ResolvedLessonSlot> slots,
  }) {
    final now = DateTime.now();
    final todayName = StudentMovementService.dayNameTr(now.weekday);
    final liveDateTimeStr =
        '${DateFormat("dd.MM.yyyy").format(now)} $todayName • Saat ${DateFormat("HH:mm").format(now)}';
    final schedDay = slots.isNotEmpty && slots.first.scheduleDayName.isNotEmpty
        ? slots.first.scheduleDayName
        : todayName;
    final isOffDayFallback =
        slots.isNotEmpty && slots.first.isOffDayFallback;
    final firstStart = slots.isNotEmpty ? slots.first.startTime : '';
    final lastEnd = slots.isNotEmpty ? slots.last.endTime : '';
    final daySpanStr = firstStart.isNotEmpty && lastEnd.isNotEmpty
        ? ' ($firstStart - $lastEnd)'
        : '';
    final liveSlot = _slotForHourFrom(slots, _liveCurrentLessonHour);
    final liveSlotRange = liveSlot.startTime.isNotEmpty
        ? (liveSlot.endTime.isNotEmpty
            ? ' • ${liveSlot.startTime} - ${liveSlot.endTime}'
            : ' • ${liveSlot.startTime}')
        : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_filled_rounded,
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'İşlem Zamanı: $liveDateTimeStr',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_view_day_rounded,
                size: 15,
                color: accentColor,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  isOffDayFallback
                      ? '$schedDay Programı (${slots.length} Ders$daySpanStr • Tatil Günü Referansı)'
                      : '$schedDay Ders Programı • Toplam ${slots.length} Ders$daySpanStr',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Aktif Dilim: $_liveCurrentLessonHour. Ders$liveSlotRange',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleLessonHourSelector({required Color accentColor}) {
    final slots = _resolvedSlots.isNotEmpty
        ? _resolvedSlots
        : _defaultLessonSlots(8);
    final activeSlot = _currentSelectedSlot;
    final activeHasRange =
        activeSlot.startTime.isNotEmpty && activeSlot.endTime.isNotEmpty;
    final multiCls = _hasMultiClassSelection;
    final schedDay = slots.first.scheduleDayName.isNotEmpty
        ? slots.first.scheduleDayName
        : StudentMovementService.dayNameTr(DateTime.now().weekday);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLiveOperationAndScheduleHeader(
          accentColor: accentColor,
          slots: slots,
        ),
        _buildVerticalSingleChecklist<int>(
          label:
              'İlgili Ders Saati ($schedDay • Toplam ${slots.length} Ders)',
          badgeText: activeHasRange
              ? '${activeSlot.lessonHour}. Ders (${activeSlot.startTime} - ${activeSlot.endTime})'
              : '${activeSlot.lessonHour}. Ders Seçili',
          accentColor: accentColor,
          selectedValue: _selectedLessonHour,
          headerTrailing: _loadingSchedule
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ders programı eşleştiriliyor...',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ],
                )
              : null,
          items: slots.map((s) {
            final showLesson = !multiCls &&
                s.lessonName.isNotEmpty &&
                s.lessonName != '${s.lessonHour}. Ders';
            final showTeacher = !multiCls && s.teacherNames.isNotEmpty;
            final timeInfo = s.startTime.isNotEmpty
                ? (s.endTime.isNotEmpty
                    ? '${s.startTime} - ${s.endTime}'
                    : s.startTime)
                : null;
            final isLiveNow = s.lessonHour == _liveCurrentLessonHour;

            String? badge;
            if (multiCls) {
              badge = 'Her Öğrencinin Kendi Şube Öğretmeni';
            } else if (showLesson && showTeacher) {
              badge = '${s.lessonName} • ${s.teacherNames.join(", ")}';
            } else if (showLesson) {
              badge = s.lessonName;
            } else if (isLiveNow) {
              badge = 'Şu Anki Ders Saati';
            } else {
              badge = timeInfo;
            }

            return (
              value: s.lessonHour,
              title:
                  '${s.lessonHour}. Ders${timeInfo != null ? "  •  $timeInfo" : ""}${isLiveNow ? "  (Şu An)" : ""}',
              subtitle: null,
              trailingBadge: badge,
            );
          }).toList(),
          onSelected: (h) {
            final picked = _slotForHourFrom(slots, h);
            setState(() {
              _selectedLessonHour = h;
              if (_activeTab == 3 &&
                  !_earlyArrivedNow &&
                  picked.startTime.isNotEmpty) {
                _earlyPlannedTimeCtrl.text = picked.startTime;
              }
            });
          },
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  multiCls
                      ? 'Çoklu şube seçili: Seçilen her öğrencinin $_selectedLessonHour. dersteki${activeHasRange ? " (${activeSlot.startTime} - ${activeSlot.endTime})" : ""} kendi şube/kur öğretmenine ayrı ayrı bildirim gönderilir.'
                      : (activeSlot.teacherNames.isNotEmpty
                          ? 'Bildirim Gidecek Ders Öğretmeni: ${activeSlot.teacherNames.join(", ")} (${activeSlot.lessonName}${activeHasRange ? " • ${activeSlot.startTime} - ${activeSlot.endTime}" : ""})'
                          : 'Öğrenci seçildiğinde $_selectedLessonHour. dersin${activeHasRange ? " (${activeSlot.startTime} - ${activeSlot.endTime})" : ""} öğretmeni otomatik çözümlenir ve bilgilendirilir.'),
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 1: GEÇ KAĞIDI VERME EKRANI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLateSlipTab(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFFD97706);
    final todayLates = todayRecords
        .where((r) => r.type == StudentMovementType.lateSlip)
        .toList();

    const presetReasons = [
      'Servis / Ulaşım Gecikmesi',
      'Trafik Yoğunluğu',
      'Sağlık / Hastane Randevusu',
      'Ailevi Mazeret (Veli Bilgisiyle)',
      'Uyuya Kalma / Bireysel Gecikme',
      'Hava Muhalefeti / Olumsuz Yol Koşulları',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        _buildStudentSelectorPanel(accentColor: accent),
        const SizedBox(height: 16),
        _buildPremiumSectionCard(
          stepBadge: 'ADIM 2 • DERSE KABUL PUSULASI',
          title: 'Geç Kağıdı Bilgileri ve Öğretmen Bildirimi',
          subtitle:
              'Geç kalan öğrenciler için anlık öğretmen bildirimi ve yoklama kaydı oluşturun',
          icon: Icons.schedule_rounded,
          accentColor: accent,
          children: [
            _buildSingleLessonHourSelector(accentColor: accent),
            const SizedBox(height: 18),
            _buildVerticalSingleChecklist<String>(
              label: 'Geç Kalma Nedeni (Alt Alta Seçim Listesi)',
              accentColor: accent,
              selectedValue: _lateReason,
              items: presetReasons
                  .map(
                    (r) => (
                      value: r,
                      title: r,
                      subtitle: null,
                      trailingBadge: _lateReason == r ? 'Seçili' : null,
                    ),
                  )
                  .toList(),
              onSelected: (r) => setState(() => _lateReason = r),
            ),
            const SizedBox(height: 16),
            _buildPremiumTextField(
              controller: _lateNotesCtrl,
              label: 'Ek Açıklama / Öğretmene İletilecek Not',
              badgeText: 'İsteğe Bağlı',
              hint:
                  'Örn: Velisi telefonla bilgi verdi, derse kabulü uygundur...',
              icon: Icons.edit_note_rounded,
              accentColor: accent,
            ),
            const SizedBox(height: 14),
            _buildPremiumSwitchCard(
              title: 'Yoklama tablosuna otomatik "Geç" olarak işlensin',
              subtitle:
                  'Öğretmenin yoklama ekranında seçili öğrenciler otomatik Geç görünür.',
              value: _lateAutoAttendance,
              accentColor: accent,
              icon: Icons.fact_check_outlined,
              onChanged: (v) => setState(() => _lateAutoAttendance = v),
            ),
            const SizedBox(height: 18),
            _buildPremiumSubmitButton(
              baseLabel:
                  'GEÇ KAĞIDI VER & DERSİ OLAN ÖĞRETMENE BİLDİRİM GÖNDER',
              icon: Icons.notifications_active_rounded,
              accentColor: accent,
              onPressed: _submitLateSlip,
            ),
          ],
        ),
        if (todayLates.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugün Verilen Geç Kağıtları (${todayLates.length})',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                ...todayLates.map(_buildTimelineRecordTile),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 2: ÇIKIŞ İZNİ & GÜVENLİK KAPI ONAYI EKRANI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExitPermissionTab(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFF0284C7);
    final pendingGateList = todayRecords
        .where(
          (r) =>
              r.status == StudentMovementStatus.pendingGate ||
              r.status == StudentMovementStatus.parentArrived,
        )
        .toList();
    final confirmedExits = todayRecords
        .where((r) => r.status == StudentMovementStatus.exitedSchool)
        .toList();

    final maxH = _resolvedSlots.isNotEmpty ? _resolvedSlots.last.lessonHour : 8;
    final remainingPreview = [
      for (int h = _selectedLessonHour; h <= maxH; h++) '$h.',
    ].join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: pendingGateList.isNotEmpty
                ? const Color(0xFFFFF7ED)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: pendingGateList.isNotEmpty
                  ? const Color(0xFFFB923C)
                  : const Color(0xFFE2E8F0),
              width: pendingGateList.isNotEmpty ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.security_rounded,
                    color: pendingGateList.isNotEmpty
                        ? const Color(0xFFEA580C)
                        : accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GÜVENLİK KAPI KONTROLÜ — Çıkış Yapacak Öğrenciler (${pendingGateList.length} Bekleyen)',
                      style: GoogleFonts.inter(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (pendingGateList.isEmpty)
                Text(
                  'Şu an kapı çıkış onayı bekleyen öğrenci bulunmuyor. İzin verildiğinde güvenlik birimine bildirim düşer ve burada listelenir.',
                  style: TextStyle(fontSize: 12.2, color: Colors.grey.shade700),
                )
              else
                Column(
                  children: pendingGateList.map(_buildActiveRadarRow).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStudentSelectorPanel(accentColor: accent),
        const SizedBox(height: 16),
        _buildPremiumSectionCard(
          stepBadge: 'ADIM 2 • GÜVENLİK & KAPI ONAYLI İZİN',
          title: 'Öğrenci Çıkış İzni Düzenle',
          subtitle:
              'Güvenlik birimine anlık çıkış bildirimi düşer; kapı onayında kalan dersler otomatik İzinli işlenir',
          icon: Icons.sensor_door_rounded,
          accentColor: accent,
          children: [
            _buildSingleLessonHourSelector(accentColor: accent),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: Color(0xFF0369A1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Güvenlik kapıdan çıkışı onayladığında öğrencinin bugünkü kalan dersleri ($remainingPreview dersler) yoklama sisteminde OTOMATİK İZİNLİ yazılacaktır.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0C4A6E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildVerticalSingleChecklist<String>(
              label: 'Çıkış Şekli (Alt Alta Seçim Listesi)',
              accentColor: accent,
              selectedValue: _exitMode,
              items: const [
                (
                  value: 'Veli Eşliğinde Çıkış',
                  title: 'Veli Eşliğinde Çıkış',
                  subtitle: null,
                  trailingBadge: 'Veli Teslimi',
                ),
                (
                  value: 'Veli Bilgisi / Onayıyla Tek Başına Çıkış',
                  title: 'Veli Bilgisi / Onayıyla Tek Başına Çıkış',
                  subtitle: null,
                  trailingBadge: 'Veli Onaylı',
                ),
                (
                  value: 'Sağlık / Hastane Sevk Çıkışı',
                  title: 'Sağlık / Hastane Sevk Çıkışı',
                  subtitle: null,
                  trailingBadge: 'Sağlık Sevk',
                ),
                (
                  value: 'Resmi / İdari Görevli Çıkışı',
                  title: 'Resmi / İdari Görevli (Takım / Kafile) Çıkışı',
                  subtitle: null,
                  trailingBadge: 'Görevli İzinli',
                ),
              ],
              onSelected: (v) => setState(() => _exitMode = v),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 680;
                final timeField = _buildPremiumTextField(
                  controller: _plannedExitTimeCtrl,
                  label: 'Planlanan Çıkış Saati',
                  hint: 'SS:DD',
                  icon: Icons.access_time_rounded,
                  accentColor: accent,
                );
                final nameF = _buildPremiumTextField(
                  controller: _receiverNameCtrl,
                  label: 'Teslim Alan Veli / Görevli Adı Soyadı',
                  badgeText: _selectedStudents.length > 1
                      ? 'Boşsa kendi velisi alınır'
                      : null,
                  hint: 'Örn: Ahmet Yılmaz / Kafile Öğretmeni',
                  icon: Icons.person_outline_rounded,
                  accentColor: accent,
                );
                final relF = _buildPremiumTextField(
                  controller: _receiverRelationCtrl,
                  label: 'Yakınlığı / Unvanı',
                  hint: 'Velisi, Annesi, Görevli Öğrt.',
                  icon: Icons.badge_outlined,
                  accentColor: accent,
                );
                final phoneF = _buildPremiumTextField(
                  controller: _receiverPhoneCtrl,
                  label: 'İletişim Telefonu',
                  hint: '05XX XXX XX XX',
                  icon: Icons.phone_outlined,
                  accentColor: accent,
                );
                if (wide) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: timeField),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: nameF),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: relF),
                          const SizedBox(width: 12),
                          Expanded(child: phoneF),
                        ],
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    timeField,
                    const SizedBox(height: 12),
                    nameF,
                    const SizedBox(height: 12),
                    relF,
                    const SizedBox(height: 12),
                    phoneF,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildVerticalSingleChecklist<String>(
              label: 'Hızlı İzin / Çıkış Gerekçesi Seçimi',
              badgeText: 'Seç veya aşağıya yaz',
              accentColor: accent,
              selectedValue: _exitReasonCtrl.text.trim().isEmpty
                  ? null
                  : _exitReasonCtrl.text.trim(),
              items: const [
                'Hastane / Diş Hekimi Randevusu',
                'Veli Talebi / Ailevi Mazeret',
                'Sağlık Rahatsızlığı / Eve İstirahat',
                'Resmi / Sportif Müsabaka & Kafile Görevi',
                'Nüfus / Resmi Kurum İşlemleri',
              ]
                  .map(
                    (r) => (
                      value: r,
                      title: r,
                      subtitle: null,
                      trailingBadge:
                          _exitReasonCtrl.text.trim() == r ? 'Seçili' : null,
                    ),
                  )
                  .toList(),
              onSelected: (r) => setState(() => _exitReasonCtrl.text = r),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _exitReasonCtrl,
              label: 'İzin / Çıkış Gerekçesi',
              badgeText: 'Zorunlu',
              hint:
                  'Örn: Diş hekimi randevusu, ilçe müsabakası kafilesi, ailevi mazeret...',
              icon: Icons.description_outlined,
              accentColor: accent,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _exitNotesCtrl,
              label: 'Güvenlik Birimine Ek Not',
              badgeText: 'İsteğe Bağlı',
              hint: 'Örn: Kapıda kimlik kontrolü yapılarak teslim edilecek...',
              icon: Icons.shield_outlined,
              accentColor: accent,
            ),
            const SizedBox(height: 18),
            _buildPremiumSubmitButton(
              baseLabel: 'ÇIKIŞ İZNİ VER & GÜVENLİK BİRİMİNE BİLDİRİM GÖNDER',
              icon: Icons.send_to_mobile_rounded,
              accentColor: accent,
              onPressed: _submitExitPermission,
            ),
          ],
        ),
        if (confirmedExits.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugün Güvenlik Onayıyla Çıkış Yapan Öğrenciler (${confirmedExits.length})',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                ...confirmedExits.map(_buildTimelineRecordTile),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 3: VELİ ERKEN ALMA & KAPI ÇAĞRI MERKEZİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEarlyPickupTab(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFF0D9488);
    final arrivedList = todayRecords
        .where(
          (r) =>
              r.status == StudentMovementStatus.parentArrived ||
              (r.type == StudentMovementType.earlyPickup &&
                  r.status == StudentMovementStatus.pendingGate),
        )
        .toList();
    final plannedList = todayRecords
        .where((r) => r.status == StudentMovementStatus.earlyPickupNotified)
        .toList();
    final completedEarlyList = todayRecords
        .where(
          (r) =>
              r.type == StudentMovementType.earlyPickup &&
              r.status == StudentMovementStatus.exitedSchool,
        )
        .toList();

    const relationOptions = [
      (
        value: 'Velisi',
        title: 'Kendi Velisi (Anne / Baba)',
        subtitle: null,
        trailingBadge: 'Standart Veli Teslimi',
      ),
      (
        value: 'Annesi',
        title: 'Annesi Teslim Alacak',
        subtitle: null,
        trailingBadge: 'Anne',
      ),
      (
        value: 'Babası',
        title: 'Babası Teslim Alacak',
        subtitle: null,
        trailingBadge: 'Baba',
      ),
      (
        value: 'Veli Onaylı Yakını',
        title: 'Veli Onaylı Yakını (Kimlik Kontrolü İle)',
        subtitle:
            'Güvenlik kapısında T.C. kimlik ve veli telefon teyidi yapılır',
        trailingBadge: 'Kimlik Kontrolü Zorunlu',
      ),
    ];

    const reasonOptions = [
      'Hastane / Doktor / Diş Hekimi Randevusu',
      'Sağlık / Rahatsızlık Nedeniyle Erken Alma',
      'Ailevi Mazeret / Şehir Dışı Yolculuk',
      'Resmi Kurum / Nüfus / Pasaport İşlemleri',
      'Sportif / Sanatsal Müsabaka & Antrenman',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        // 1) ŞU AN OKULA GELEN / KAPIDA BEKLEYEN VELİLER PANELİ
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: arrivedList.isNotEmpty
                ? const Color(0xFFECFDF5)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: arrivedList.isNotEmpty
                  ? const Color(0xFF10B981)
                  : const Color(0xFFE2E8F0),
              width: arrivedList.isNotEmpty ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.where_to_vote_rounded,
                    color: arrivedList.isNotEmpty
                        ? const Color(0xFF059669)
                        : accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '📍 ŞU AN OKULA GELEN VELİLER — ÇIKIŞA HAZIRLANAN ÖĞRENCİLER (${arrivedList.length})',
                      style: GoogleFonts.inter(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (arrivedList.isEmpty)
                Text(
                  'Şu an kapıda bekleyen veli çağrısı bulunmuyor. Veli kendi panelinden "Okula Geldim" dediğinde veya aşağıdan işaretlendiğinde anında burada görünür ve dersin öğretmenine bildirim gider.',
                  style: TextStyle(fontSize: 12.2, color: Colors.grey.shade700),
                )
              else
                Column(
                  children: arrivedList.map(_buildActiveRadarRow).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2) ÖNCEDEN HABER VERİLEN PLANLI ERKEN ALMALAR PANELİ
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: plannedList.isNotEmpty
                ? const Color(0xFFF0FDFA)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: plannedList.isNotEmpty
                  ? const Color(0xFF5EEAD4)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '📅 BUGÜN ÖNCEDEN HABER VERİLEN PLANLI ERKEN ALMALAR (${plannedList.length})',
                      style: GoogleFonts.inter(
                        fontSize: 13.6,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (plannedList.isEmpty)
                Text(
                  'Bugün için bekleyen planlı erken alma ön bildirimi yok. Veliler kendi panellerinden önceden saat bildirebilir veya telefonla arayan veliler için aşağıdan kayıt açabilirsiniz.',
                  style: TextStyle(fontSize: 12.2, color: Colors.grey.shade700),
                )
              else
                Column(
                  children: plannedList.map(_buildActiveRadarRow).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3) İDARE / GÜVENLİK TARAFINDAN ERKEN ALMA KAYDI OLUŞTURMA
        _buildStudentSelectorPanel(accentColor: accent),
        const SizedBox(height: 16),
        _buildPremiumSectionCard(
          stepBadge: 'ADIM 2 • VELİ ERKEN ALMA & KAPI ÇAĞRI SİSTEMİ',
          title: 'Erken Alma Ön Bildirimi veya Anlık "Veli Geldi" Çağrısı',
          subtitle:
              'Telefonla arayan veya doğrudan kapıya gelen veliler için doğru zamanda öğretmen ve güvenlik koordinasyonu',
          icon: Icons.directions_car_filled_rounded,
          accentColor: accent,
          children: [
            _buildVerticalSingleChecklist<bool>(
              label: 'Veli Bildirim Zamanlaması (Alt Alta Seçim Listesi)',
              accentColor: accent,
              selectedValue: _earlyArrivedNow,
              items: const [
                (
                  value: false,
                  title: 'Önceden Haber Verdi (Planlı Saatte Alacak)',
                  subtitle:
                      'İdare, güvenlik ve ilgili ders öğretmenine ön bilgi gider; veli geldiğinde tek tıkla çağrı başlatılır.',
                  trailingBadge: 'Ön Bildirim',
                ),
                (
                  value: true,
                  title: 'Veli Şu An Okula Geldi / Kapıda Bekliyor',
                  subtitle:
                      'Öğrencinin ŞU AN DERSİ OLAN öğretmenine anında "Eşyalarıyla çıkışa yönlendirin" bildirimi gönderilir.',
                  trailingBadge: 'Anlık Çağrı',
                ),
              ],
              onSelected: (v) => setState(() => _earlyArrivedNow = v),
            ),
            if (!_earlyArrivedNow) ...[
              const SizedBox(height: 16),
              _buildSingleLessonHourSelector(accentColor: accent),
            ],
            const SizedBox(height: 16),
            _buildVerticalSingleChecklist<String>(
              label: 'Teslim Alacak Kişi Yakınlığı (Alt Alta Seçim Listesi)',
              accentColor: accent,
              selectedValue: _earlyRelation,
              items: relationOptions,
              onSelected: (v) => setState(() => _earlyRelation = v),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 680;
                final timeField = _buildPremiumTextField(
                  controller: _earlyPlannedTimeCtrl,
                  label: _earlyArrivedNow
                      ? 'Geliş Saati (Şu An)'
                      : 'Planlanan Alış Saati',
                  hint: 'Örn: 14:30',
                  icon: Icons.access_time_filled_rounded,
                  accentColor: accent,
                  readOnly: _earlyArrivedNow,
                  suffix: _earlyArrivedNow
                      ? null
                      : IconButton(
                          tooltip: 'Saat Seç',
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _earlyPlannedTimeCtrl.text =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                        ),
                );
                final nameField = _buildPremiumTextField(
                  controller: _earlyReceiverNameCtrl,
                  label: 'Teslim Alacak Kişi Adı Soyadı',
                  badgeText: _selectedStudents.length > 1
                      ? 'Boşsa kendi velisi alınır'
                      : null,
                  hint: 'Örn: Ayşe Yılmaz',
                  icon: Icons.person_outline_rounded,
                  accentColor: accent,
                );
                final phoneField = _buildPremiumTextField(
                  controller: _earlyReceiverPhoneCtrl,
                  label: 'Veli / Alıcı İletişim Telefonu',
                  hint: '05XX XXX XX XX',
                  icon: Icons.phone_outlined,
                  accentColor: accent,
                );
                final plateField = _buildPremiumTextField(
                  controller: _earlyPlateCtrl,
                  label: 'Araç Plakası / Kapı Notu',
                  badgeText: 'İsteğe Bağlı',
                  hint: 'Örn: 06 ABC 123 / Ön Kapı',
                  icon: Icons.directions_car_outlined,
                  accentColor: accent,
                );

                if (wide) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: timeField),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: nameField),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: phoneField),
                          const SizedBox(width: 12),
                          Expanded(child: plateField),
                        ],
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    timeField,
                    const SizedBox(height: 12),
                    nameField,
                    const SizedBox(height: 12),
                    phoneField,
                    const SizedBox(height: 12),
                    plateField,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildVerticalSingleChecklist<String>(
              label: 'Erken Alma Nedeni (Alt Alta Seçim Listesi)',
              accentColor: accent,
              selectedValue:
                  reasonOptions.contains(_earlyReason) ? _earlyReason : null,
              items: reasonOptions
                  .map(
                    (r) => (
                      value: r,
                      title: r,
                      subtitle: null,
                      trailingBadge: _earlyReason == r ? 'Seçili' : null,
                    ),
                  )
                  .toList(),
              onSelected: (v) => setState(() => _earlyReason = v),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _earlyNotesCtrl,
              label: 'Öğretmen ve Güvenlik Birimine Ek Not',
              badgeText: 'İsteğe Bağlı',
              hint:
                  'Örn: Beslenme çantası ve montuyla birlikte danışmaya yönlendirilsin...',
              icon: Icons.notes_rounded,
              accentColor: accent,
            ),
            const SizedBox(height: 18),
            _buildPremiumSubmitButton(
              baseLabel: _earlyArrivedNow
                  ? 'VELİ OKULA GELDİ — ŞU ANKİ ÖĞRETMENE & GÜVENLİĞE BİLDİR'
                  : 'PLANLI ERKEN ALMA ÖN BİLDİRİMİ KAYDET & BİLDİR',
              icon: _earlyArrivedNow
                  ? Icons.where_to_vote_rounded
                  : Icons.event_available_rounded,
              accentColor: accent,
              onPressed: _submitEarlyPickup,
            ),
          ],
        ),
        if (completedEarlyList.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugün Veliye Erken Teslim Edilen Öğrenciler (${completedEarlyList.length})',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                ...completedEarlyList.map(_buildTimelineRecordTile),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 4: REVİR SEVK & SAĞLIK İŞLEMLERİ AÇIK DOSYA EKRANI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInfirmaryTab(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFFE11D48);
    final openReferrals = todayRecords
        .where((r) => r.status == StudentMovementStatus.inInfirmary)
        .toList();
    final completedReferrals = todayRecords
        .where(
          (r) =>
              r.type == StudentMovementType.infirmary &&
              r.status == StudentMovementStatus.completed,
        )
        .toList();

    const quickComplaints = [
      'Baş ağrısı / Baş dönmesi',
      'Karın ağrısı / Mide bulantısı',
      'Ateş / Halsizlik',
      'Düşme / Yaralanma / Pansuman',
      'Burun kanaması',
      'Boğaz / Diş ağrısı',
      'Alerjik şikayet / Nefes darlığı',
    ];

    final currentParts = _infirmaryComplaintCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final selectedQuickSet =
        quickComplaints.where((c) => currentParts.contains(c)).toSet();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: openReferrals.isNotEmpty
                ? const Color(0xFFFFF1F2)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: openReferrals.isNotEmpty
                  ? const Color(0xFFFB7185)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.medical_services_rounded, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'REVİRDE AÇIK DOSYALAR — Müdahale Bekleyen Öğrenciler (${openReferrals.length})',
                      style: GoogleFonts.inter(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Buradaki her açık dosya Destek Hizmetleri > Sağlık İşlemleri (Revir) ekranında da anlık görünür. Revir işlemi tamamlandığında Veli + Yönlendiren + Ders Öğretmenine otomatik bildirim gider.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (openReferrals.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...openReferrals.map(_buildActiveRadarRow),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStudentSelectorPanel(accentColor: accent),
        const SizedBox(height: 16),
        _buildPremiumSectionCard(
          stepBadge: 'ADIM 2 • SAĞLIK & REVİR SEVK',
          title: 'Revir Sevk Kağıdı Düzenle',
          subtitle:
              'Revir biriminde anlık açık sağlık dosyası açılır ve ders öğretmeni bilgilendirilir',
          icon: Icons.local_hospital_rounded,
          accentColor: accent,
          children: [
            _buildSingleLessonHourSelector(accentColor: accent),
            const SizedBox(height: 16),
            _buildVerticalMultiChecklist<String>(
              label: 'Hızlı Şikayet Seçimi (Çoklu İşaretlenebilir)',
              badgeText: selectedQuickSet.isNotEmpty
                  ? '${selectedQuickSet.length} Seçili'
                  : 'Çoklu Seçim',
              accentColor: accent,
              selectedValues: selectedQuickSet,
              items: quickComplaints
                  .map(
                    (c) => (
                      value: c,
                      title: c,
                      subtitle: null,
                      trailingBadge:
                          selectedQuickSet.contains(c) ? 'Eklendi' : null,
                    ),
                  )
                  .toList(),
              onToggle: (c, nextSel) {
                setState(() {
                  final parts = _infirmaryComplaintCtrl.text
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  if (nextSel) {
                    if (!parts.contains(c)) parts.add(c);
                  } else {
                    parts.remove(c);
                  }
                  _infirmaryComplaintCtrl.text = parts.join(', ');
                });
              },
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _infirmaryComplaintCtrl,
              label: 'Öğrencinin Şikayeti / Sevk Nedeni',
              badgeText: 'Zorunlu',
              hint: 'Şikayet detayını yazın veya yukarıdan işaretleyin...',
              icon: Icons.healing_outlined,
              accentColor: accent,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _buildVerticalSingleChecklist<String>(
              label: 'Öncelik Durumu',
              accentColor: accent,
              selectedValue: _infirmaryUrgency,
              items: const [
                (
                  value: 'Normal',
                  title: 'Normal Sevk',
                  subtitle: null,
                  trailingBadge: 'Standart Kontrol',
                ),
                (
                  value: 'Öncelikli',
                  title: 'Öncelikli Kontrol',
                  subtitle: null,
                  trailingBadge: 'Yakın Gözlem',
                ),
                (
                  value: 'Acil',
                  title: 'ACİL DURUM',
                  subtitle: null,
                  trailingBadge: 'Acil Müdahale',
                ),
              ],
              onSelected: (v) => setState(() => _infirmaryUrgency = v),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _infirmaryNotesCtrl,
              label: 'Revire İletilecek Ek Bilgi',
              badgeText: 'İsteğe Bağlı',
              hint:
                  'Örn: Bilinen alerji durumu, yanında refakatçi öğrenci var...',
              icon: Icons.notes_rounded,
              accentColor: accent,
            ),
            const SizedBox(height: 18),
            _buildPremiumSubmitButton(
              baseLabel: 'REVİR KAĞIDI VER & REVİRDE AÇIK DOSYA OLUŞTUR',
              icon: Icons.medical_information_rounded,
              accentColor: accent,
              onPressed: _submitInfirmaryReferral,
            ),
          ],
        ),
        if (completedReferrals.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugün Tamamlanan Revir İşlemleri (${completedReferrals.length})',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                ...completedReferrals.map(_buildTimelineRecordTile),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 4: ÖĞRENCİ GÖRÜŞME & YOK YAZILMAMA KORUMASI EKRANI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInterviewTab(List<StudentMovementRecord> todayRecords) {
    const accent = Color(0xFF7C3AED);
    final activeMeetings = todayRecords
        .where((r) => r.status == StudentMovementStatus.inMeeting)
        .toList();

    final slots = _resolvedSlots.isNotEmpty
        ? _resolvedSlots
        : _defaultLessonSlots(8);
    final multiCls = _hasMultiClassSelection;

    const quickTopics = [
      'Bireysel öğrenci görüşmesi',
      'Akran uzlaştırma / grup görüşmesi',
      'Akademik hedef ve motivasyon takibi',
      'Sınav kaygısı ve verimli çalışma',
      'İdari / ÖDDK bilgi alma görüşmesi',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
      children: [
        if (activeMeetings.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFC4B5FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.record_voice_over_rounded,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Şu An Görüşmede Olan Öğrenciler (${activeMeetings.length})',
                        style: GoogleFonts.inter(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF4C1D95),
                        ),
                      ),
                    ),
                    if (activeMeetings.length > 1)
                      OutlinedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () async {
                                setState(() => _isSubmitting = true);
                                try {
                                  for (final m in activeMeetings) {
                                    await _service.completeStudentInterview(m);
                                  }
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF059669),
                                      content: Text(
                                        '✓ ${activeMeetings.length} öğrencinin görüşmesi tamamlandı.',
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _isSubmitting = false);
                                  }
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(color: accent.withValues(alpha: 0.4)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.done_all_rounded, size: 15),
                        label: const Text(
                          'Tümünü Bitir',
                          style: TextStyle(
                            fontSize: 11.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ...activeMeetings.map(_buildActiveRadarRow),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildStudentSelectorPanel(accentColor: accent),
        const SizedBox(height: 16),

        _buildPremiumSectionCard(
          stepBadge: 'ADIM 2 • GÖRÜŞME & YOKLAMA KORUMASI',
          title: 'Öğrenci Görüşme Kaydı ve Yoklama Koruması',
          subtitle:
              'Bireysel veya çoklu öğrenci görüşmelerinde ilgili ders öğretmenlerine bildirim gider, öğrenciler yok yazılmaz',
          icon: Icons.record_voice_over_rounded,
          accentColor: accent,
          children: [
            _buildVerticalSingleChecklist<String>(
              label: 'Görüşme Yapılan Birim',
              accentColor: accent,
              selectedValue: _interviewUnit,
              items: const [
                (
                  value: 'Rehberlik / PDR Servisi Görüşmesi',
                  title: 'Rehberlik / PDR Servisi Görüşmesi',
                  subtitle: null,
                  trailingBadge: 'PDR Birimi',
                ),
                (
                  value: 'Müdür / Müdür Yardımcısı Görüşmesi',
                  title: 'Müdür / Müdür Yardımcısı Görüşmesi',
                  subtitle: null,
                  trailingBadge: 'Okul İdaresi',
                ),
                (
                  value: 'Sınıf / Ders Öğretmeni Görüşmesi',
                  title: 'Sınıf / Ders Öğretmeni Görüşmesi',
                  subtitle: null,
                  trailingBadge: 'Öğretmen Görüşmesi',
                ),
                (
                  value: 'ÖDDK / Kurul Görüşmesi',
                  title: 'ÖDDK / Kurul Görüşmesi',
                  subtitle: null,
                  trailingBadge: 'Kurul İşlemi',
                ),
              ],
              onSelected: (v) => setState(() => _interviewUnit = v),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _interviewerNameCtrl,
              label: 'Görüşmeyi Yapan Yetkili',
              hint: 'Ad Soyad',
              icon: Icons.person_pin_rounded,
              accentColor: accent,
            ),
            const SizedBox(height: 18),

            // Canlı İşlem Zamanı + Günlük Ders Çizelgesi Özeti
            _buildLiveOperationAndScheduleHeader(
              accentColor: accent,
              slots: slots,
            ),

            // Ders Saatleri Çoklu Seçici (Alt Alta Çeklist)
            _buildVerticalMultiChecklist<int>(
              label:
                  'Görüşmenin Kapsadığı Ders Saat(ler)i (${slots.isNotEmpty && slots.first.scheduleDayName.isNotEmpty ? slots.first.scheduleDayName : StudentMovementService.dayNameTr(DateTime.now().weekday)} • Toplam ${slots.length} Ders)',
              badgeText: '${_selectedInterviewHours.length} Ders Seçili',
              accentColor: accent,
              selectedValues: _selectedInterviewHours,
              headerTrailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loadingSchedule) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedInterviewHours = {_liveCurrentLessonHour};
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Sadece Aktif Ders',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedInterviewHours =
                            slots.map((s) => s.lessonHour).toSet();
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Tüm Dersler',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              items: slots.map((slot) {
                final showLesson = !multiCls &&
                    slot.lessonName.isNotEmpty &&
                    slot.lessonName != '${slot.lessonHour}. Ders';
                final showTeacher = !multiCls && slot.teacherNames.isNotEmpty;
                final timeInfo = slot.startTime.isNotEmpty
                    ? (slot.endTime.isNotEmpty
                        ? '${slot.startTime} - ${slot.endTime}'
                        : slot.startTime)
                    : null;
                final isLiveNow = slot.lessonHour == _liveCurrentLessonHour;
                String? badge;
                if (multiCls) {
                  badge = 'Her Öğrencinin Kendi Şube Öğretmeni';
                } else if (showLesson && showTeacher) {
                  badge = '${slot.lessonName} • ${slot.teacherNames.join(", ")}';
                } else if (showLesson) {
                  badge = slot.lessonName;
                } else if (isLiveNow) {
                  badge = 'Şu Anki Ders Saati';
                } else {
                  badge = timeInfo;
                }
                return (
                  value: slot.lessonHour,
                  title:
                      '${slot.lessonHour}. Ders${timeInfo != null ? "  •  $timeInfo" : ""}${isLiveNow ? "  (Şu An)" : ""}',
                  subtitle: null,
                  trailingBadge: badge,
                );
              }).toList(),
              onToggle: (hour, nextSel) {
                setState(() {
                  if (nextSel) {
                    _selectedInterviewHours.add(hour);
                  } else {
                    _selectedInterviewHours.remove(hour);
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            _buildVerticalSingleChecklist<String>(
              label: 'Hızlı Görüşme Konusu Şablonları',
              badgeText: 'Seç veya aşağıya yaz',
              accentColor: accent,
              selectedValue: _interviewTopicCtrl.text.trim().isEmpty
                  ? null
                  : _interviewTopicCtrl.text.trim(),
              items: quickTopics
                  .map(
                    (t) => (
                      value: t,
                      title: t,
                      subtitle: null,
                      trailingBadge:
                          _interviewTopicCtrl.text.trim() == t ? 'Seçili' : null,
                    ),
                  )
                  .toList(),
              onSelected: (t) => setState(() => _interviewTopicCtrl.text = t),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _interviewTopicCtrl,
              label: 'Görüşme Konusu / Kısa Bilgi',
              hint:
                  'Örn: Bireysel rehberlik görüşmesi, akran arabuluculuk, sınav kaygısı...',
              icon: Icons.chat_bubble_outline_rounded,
              accentColor: accent,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _buildPremiumTextField(
              controller: _interviewNotesCtrl,
              label: 'Ders Öğretmenine İletilecek Ek Not',
              badgeText: 'İsteğe Bağlı',
              hint: 'Örn: Görüşme bitiminde derse katılım sağlayacaktır...',
              icon: Icons.sticky_note_2_outlined,
              accentColor: accent,
            ),
            const SizedBox(height: 14),
            _buildPremiumSwitchCard(
              title:
                  'Öğrenci Yok Yazılmasın — Seçili derslerde otomatik "İzinli" korumasına al',
              subtitle:
                  'Öğretmenlerin yoklama ekranında seçili tüm öğrenciler "Görüşmede / İzinli" görünür ve devamsız düşmez.',
              value: _interviewProtectAttendance,
              accentColor: accent,
              icon: Icons.verified_user_rounded,
              onChanged: (v) =>
                  setState(() => _interviewProtectAttendance = v),
            ),
            const SizedBox(height: 18),
            _buildPremiumSubmitButton(
              baseLabel:
                  'GÖRÜŞMEYİ BAŞLAT & İLGİLİ DERS ÖĞRETMENLERİNE BİLDİR',
              icon: Icons.notifications_active_rounded,
              accentColor: accent,
              onPressed: _submitInterview,
            ),
          ],
        ),
      ],
    );
  }
}
