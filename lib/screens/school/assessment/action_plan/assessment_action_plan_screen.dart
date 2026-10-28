import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/term_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../widgets/edukn_logo.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../services/user_permission_service.dart';
import '../../../../services/course_track_resolver.dart';
class AssessmentActionPlanScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final AssessmentActionPlan? existingPlan;
  
  // Initial parameters for new plans
  final List<String>? initialExamIds;
  final Map<String, double>? initialThresholds;
  final double? initialGlobalThreshold;
  final String? initialClassLevel;

  const AssessmentActionPlanScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.existingPlan,
    this.initialExamIds,
    this.initialThresholds,
    this.initialGlobalThreshold,
    this.initialClassLevel,
  }) : super(key: key);

  @override
  _AssessmentActionPlanScreenState createState() =>
      _AssessmentActionPlanScreenState();
}

class _AssessmentActionPlanScreenState extends State<AssessmentActionPlanScreen>
    with SingleTickerProviderStateMixin {
  final AssessmentService _service = AssessmentService();
  late TabController _tabController;
  String _userName = 'Yükleniyor...';

  // Auto-save state
  String? _planId;
  Future<String?>? _createFuture;
  bool _isAutoSaving = false;
  DateTime? _lastSaved;
  Map<String, dynamic> _studentInfo = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
    _loadUserName();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
          _filterExams();
        });
      }
    });
  }

  Future<void> _loadUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String resolvedName = await UserPermissionService.resolveUserFullName(
          user.uid,
          institutionId: widget.institutionId,
          fallback: '',
        );
        if (resolvedName.isEmpty || resolvedName == 'Sistem Yöneticisi') {
          final ud = await UserPermissionService.loadUserData();
          resolvedName = (ud?['fullName'] ?? ud?['displayName'] ?? ud?['name'] ?? '').toString().trim();
          if (resolvedName.isEmpty && (ud?['role'] == 'admin' || ud?['role'] == 'superadmin')) {
            resolvedName = (ud?['adminFullName'] ?? ud?['schoolName'] ?? '').toString().trim();
          }
        }
        if ((resolvedName.isEmpty || resolvedName == 'Sistem Yöneticisi') &&
            user.displayName != null &&
            user.displayName!.trim().isNotEmpty) {
          resolvedName = user.displayName!.trim();
        }

        if (resolvedName.isNotEmpty &&
            resolvedName != 'Sistem Yöneticisi' &&
            resolvedName != 'Kullanıcı' &&
            mounted) {
          setState(() {
            _userName = resolvedName;
          });

          // Eski kayıtlarda 'Kullanıcı' veya 'Sistem Yöneticisi' olarak kalmış plan varsa veritabanında asıl adla güncelle
          if (_planId != null && _planId!.isNotEmpty) {
            final p = widget.existingPlan;
            if (p != null && (p.creatorName.isEmpty || p.creatorName == 'Kullanıcı' || p.creatorName == 'Sistem Yöneticisi')) {
              FirebaseFirestore.instance
                  .collection('assessment_action_plans')
                  .doc(_planId)
                  .update({'creatorName': resolvedName})
                  .catchError((_) {});
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }

  // Filters & Selection
  List<TrialExam> _allExams = [];
  List<TrialExam> _filteredExams = [];
  Set<String> _selectedExamIds = {};
  String? _selectedClassLevel;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Thresholds (Subject -> % Success Threshold)
  Map<String, double> _subjectThresholds = {};
  List<String> _availableSubjects = [];

  // Data
  bool _isLoading = true;
  bool _isProcessing = false;
  
  // Results: Map<Branch, Map<Subject, Map<Outcome, Map<String, dynamic>>>>
  // Contains: { 'correct': int, 'total': int, 'students': List<Map<String, dynamic>> }
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> _outcomeStats = {};
  
  // Teachers: Map<Branch, Map<Subject, String>>
  Map<String, Map<String, String>> _branchTeachers = {};
  // Tüm atamalar: [{'cls','lesson','teachers'}] — bulanık eşleşme için
  List<Map<String, String>> _allAssignments = [];
  // Fallback: Map<Subject, String> — used when branch doesn't match className
  Map<String, String> _subjectTeacherFallback = {};

  // Action Plans: Map<Branch_Subject, Map<String, dynamic>>
  // Contains: { 'problemSource': String, 'actionPlan': String, 'status': String }
  Map<String, Map<String, dynamic>> _branchActionPlans = {};

  // View Filters for Step 2 & 3 (Multi-select)
  List<String> _selectedViewBranches = [];
  List<String> _selectedViewSubjects = [];
  double _globalThreshold = 70.0;

  // Student Subject Performance: Map<Branch, Map<Subject, Map<StudentId, Map<String, dynamic>>>>
  // Contains: { 'correct': int, 'total': int, 'name': String, 'no': String }
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> _studentSubjectStats = {};

  bool _showOnlyCritical = true; // Varsayılan: sadece kritik kazanımlar
  bool _showOnlyCriticalStudents = true; // Varsayılan: sadece kritik (riskli) öğrenciler

  // Student tracking state
  final Set<String> _selectedStudentKeys = {}; // 'branch_subject_studentKey'
  // studentTasks: 'branch_subject_studentKey' -> List<Map<String,dynamic>>
  // Each task: {'type': String, 'label': String, 'done': bool}
  Map<String, List<Map<String, dynamic>>> _studentTasks = {};
  // parentNotified: 'branch_subject_studentKey' -> bool
  Map<String, bool> _parentNotified = {};
  // studentStatus: 'branch_subject_studentKey' -> String
  Map<String, String> _studentStatus = {};

  static const List<Map<String, dynamic>> _taskTypes = [
    {'type': 'soru', 'label': 'Soru Çözümü', 'icon': Icons.quiz_outlined},
    {'type': 'konu', 'label': 'Konu Özeti', 'icon': Icons.menu_book_outlined},
    {'type': 'video', 'label': 'Video İzleme', 'icon': Icons.play_circle_outline},
    {'type': 'etut', 'label': 'Etüt Çalışması', 'icon': Icons.school_outlined},
    {'type': 'odev', 'label': 'Ödev Takibi', 'icon': Icons.assignment_outlined},
    {'type': 'test', 'label': 'Kazanım Testi', 'icon': Icons.check_circle_outline},
  ];

  final List<String> _predefinedActionPlans = [
    'Konu anlatımı tekrarı',
    'Ek soru çözümü saatleri',
    'Ödev takip çizelgesi',
    'Birebir etüt çalışması',
    'Grup etüt çalışması',
    'Kazanım değerlendirme testi',
    'Veli bilgilendirme ve işbirliği',
    'Rehberlik görüşmesi',
    'Diğer',
  ];

  String? _userRole;
  final Map<String, TextEditingController> _otherActionPlanControllers = {};

  // Öğretmenin kendi ders atamaları: [{'cls': '701', 'lesson': 'Matematik'}]
  // Rol/atama bilgisi yüklenmeden istatistik hesaplanmasın diye bekletilir.
  final Completer<void> _rolesReady = Completer<void>();
  List<Map<String, String>> _myAssignments = [];

  String _normKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ığüşöç]'), '');

  /// Normalize edilmiş ders adı İngilizce mi? (ör. "ingilizce", "yabancidilingilizce", "english")
  bool _isEnglishLesson(String normLesson) =>
      normLesson.contains('ingilizce') ||
      normLesson.contains('i̇ngilizce') ||
      normLesson.contains('english');

  bool _teacherDefaultsApplied = false;
  bool get _isTeacherRole {
    final r = (_userRole ?? '').toLowerCase();
    return r == 'teacher' || r.contains('teacher') || r.contains('öğretmen') || r.contains('ogretmen');
  }

  // Kurs Listesi (kur) bilgisi: kurlu derslerde şube yerine kur kullanılır.
  CourseTrackResolver _tracks = CourseTrackResolver.empty;
  Map<String, TrackSlot> _trackSlotsByLabel = {};
  Set<String> _myIds = {};
  Set<String> _myNames = {};

  bool get _restrictToMyClasses =>
      _isTeacherRole &&
      (_myAssignments.isNotEmpty || _trackSlotsByLabel.values.any(_slotIsMine));

  bool _slotIsMine(TrackSlot slot) {
    if (slot.teacherIds.any(_myIds.contains)) return true;
    return slot.teacherNames.any((t) {
      final tn = _normKey(t);
      return tn.isNotEmpty &&
          _myNames.any((m) {
            final mn = _normKey(m);
            return mn.isNotEmpty && (tn == mn || tn.contains(mn) || mn.contains(tn));
          });
    });
  }

  /// Kurs dersi (ör. İngilizce) ise öğrencinin kurs şubesini döndürür;
  /// kurs dersinde kaydı olmayan öğrenciyi kurs şubesine dahil etmez (null döner).
  /// Normal derslerde öğrencinin kendi sınıf şubesini (rawBranch) döndürür.
  String? _trackBranchFor(
    dynamic result,
    String subject,
    String rawBranch, {
    String? classLevel,
  }) {
    if (_tracks.isEmpty) return rawBranch;
    if (_tracks.hasTrackForBranchOrLevel(
      subject,
      rawBranch: rawBranch,
      classLevel: classLevel,
    )) {
      final sid = (result['systemStudentId'] ?? result['studentId'] ?? result['id'] ?? '').toString().trim();
      final no = (result['studentNo'] ?? result['studentNumber'] ?? result['number'] ?? '').toString().trim();
      final tc = (result['tcNo'] ?? '').toString().trim();
      final name = (result['name'] ?? result['studentName'] ?? '').toString().trim();

      final slot = _tracks.slotForStudent(
        studentId: sid,
        studentNo: no,
        tcNo: tc,
        studentName: name,
        subject: subject,
        rawBranch: rawBranch,
        classLevel: classLevel,
      );
      return slot != null ? _trackShortName(slot) : null;
    }
    return rawBranch;
  }

  /// Kurs şubesinin adı (ör. "701", "501", "601"). Şube Eylem Planında şube seçildiğinde
  /// kurs dersinin de aynı şube altında (o kurs şubesindeki öğrencilerin kazanımlarına göre)
  /// listelenmesi için doğrudan alt grup adı kullanılır.
  String _trackShortName(TrackSlot slot) {
    final sub = slot.subGroupName.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sub.endsWith(' Kur')) {
      return sub.substring(0, sub.length - 4).trim();
    }
    return sub;
  }

  /// Şube etiketi + ders için kur (yoksa null).
  TrackSlot? _trackSlotFor(String branch, String subject) {
    final cleanBranch = branch.endsWith(' Kur')
        ? branch.substring(0, branch.length - 4).trim()
        : branch.trim();
    for (final s in _trackSlotsByLabel.values) {
      final short = _trackShortName(s);
      final rawSub = s.subGroupName.replaceAll(RegExp(r'\s+'), ' ').trim();
      final matchesBranch = short == cleanBranch ||
          rawSub == cleanBranch ||
          s.label == cleanBranch ||
          s.label == branch;
      if (matchesBranch && CourseTrackResolver.lessonMatches(s.lessonName, subject)) {
        return s;
      }
    }
    return null;
  }

  bool _isMyAssignment(String branch, String subject) {
    // Kur etiketi ise: kurun öğretmeni ben miyim?
    final slot = _trackSlotFor(branch, subject);
    if (slot != null) return _slotIsMine(slot);

    final b = _normKey(branch);
    final s = _normKey(subject);
    // Kurs Listesi tanımlıysa İngilizce muafiyeti uygulanmaz (kur üzerinden belirlenir).
    final englishExempt = _trackSlotsByLabel.isEmpty;
    return _myAssignments.any((a) {
      final cb = _normKey(a['cls'] ?? '');
      final cl = _normKey(a['lesson'] ?? '');
      final classOk = cb == b || (englishExempt && _isEnglishLesson(cl)); // İngilizce: tüm şubeler muaf
      final lessonOk = cl.isNotEmpty && s.isNotEmpty && (cl == s || cl.contains(s) || s.contains(cl));
      return classOk && lessonOk;
    });
  }



  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    for (var controller in _otherActionPlanControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Load Exams
      // Existing plans must load their own exams regardless of the currently selected term,
      // otherwise another user (e.g. admin) with a different term would see an empty plan.
      final String? activeTermId = widget.existingPlan != null
          ? null
          : (await TermService().getSelectedTermId() ?? await TermService().getActiveTermId());
      final examsStream = _service.getTrialExams(widget.institutionId, termId: activeTermId);
      examsStream.first.then((exams) async {
        // Öğretmen atamaları yüklenmeden hesaplama yapılmasın
        await _rolesReady.future;
        if (mounted) {
          setState(() {
            _allExams = exams;
            _filterExams();
            _isLoading = false;
          });
          
          if (widget.existingPlan != null) {
            _loadExistingPlanData();
          } else if (widget.initialExamIds != null) {
            _loadInitialParameters();
          }
        }
      });

      // Load Lesson Assignments for Teachers
      // When schoolTypeId is empty (general account), query without that filter
      Query assignmentsQuery = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true);

      if (widget.schoolTypeId.isNotEmpty) {
        assignmentsQuery = assignmentsQuery.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
      }

      final assignmentsSnapshot = await assignmentsQuery.get();

      Map<String, Map<String, String>> teacherMap = {};
      // Fallback: subject → teacher (ignoring branch), used when branch doesn't match
      Map<String, String> subjectTeacherFallback = {};

      // Giriş yapan kullanıcının kimliği (öğretmen filtresi için)
      final authUser = FirebaseAuth.instance.currentUser;
      String? role;
      final myIds = <String>{if (authUser != null) authUser.uid};
      final myNames = <String>{};
      if (authUser != null) {
        try {
          // Gerçek kullanıcı kaydı (users/{uid} olmayabilir; authUserId ile eşleşen aslı doc)
          final ud = await UserPermissionService.loadUserData();
          role = ud?['role']?.toString();
          for (final k in ['id', 'teacherId', 'authUserId', 'originalDocId']) {
            final v = ud?[k]?.toString() ?? '';
            if (v.isNotEmpty) myIds.add(v);
          }
          for (final k in ['fullName', 'name', 'displayName']) {
            final v = ud?[k]?.toString().trim() ?? '';
            if (v.isNotEmpty) myNames.add(v);
          }
        } catch (e) {
          debugPrint('Error loading user doc: $e');
        }
      }
      final List<Map<String, String>> myAssignments = [];
      final List<Map<String, String>> allAssignments = [];

      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        String className = data['className'] ?? '';
        String lessonName = data['lessonName'] ?? '';
        List<dynamic> teacherNames = data['teacherNames'] ?? [];
        final List<dynamic> teacherIds = data['teacherIds'] ?? [];
        
        if (className.isNotEmpty && lessonName.isNotEmpty && teacherNames.isNotEmpty) {
          allAssignments.add({
            'cls': className,
            'lesson': lessonName,
            'teachers': teacherNames.join(', '),
          });
        }

        if (className.isNotEmpty && lessonName.isNotEmpty) {
          final mine = teacherIds.any((t) => myIds.contains(t.toString())) ||
              myIds.contains((data['teacherId'] ?? '').toString()) ||
              teacherNames.any((t) {
                final tn = _normKey(t.toString());
                return tn.isNotEmpty && myNames.any((m) {
                  final mn = _normKey(m);
                  return mn.isNotEmpty && (tn == mn || tn.contains(mn) || mn.contains(tn));
                });
              });
          if (mine) myAssignments.add({'cls': className, 'lesson': lessonName});
        }
        
        if (lessonName.isNotEmpty && teacherNames.isNotEmpty) {
          final teacherStr = teacherNames.join(', ');
          // Primary: class + lesson lookup
          if (className.isNotEmpty) {
            teacherMap.putIfAbsent(className, () => {});
            teacherMap[className]![lessonName] = teacherStr;
          }
          // Fallback: subject only (first assignment wins)
          subjectTeacherFallback.putIfAbsent(lessonName, () => teacherStr);
        }
      }

      // Kurs Listesi'ndeki kurlar (kurlu dersler için şube yerine kur kullanılır)
      final tracks = await CourseTrackResolver.load(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );

      if (mounted) {
        setState(() {
          _branchTeachers = teacherMap;
          _subjectTeacherFallback = subjectTeacherFallback;
          _userRole = role;
          _myAssignments = myAssignments;
          _allAssignments = allAssignments;
          _myIds = myIds;
          _myNames = myNames;
          _tracks = tracks;
          _trackSlotsByLabel = tracks.allSlotsByLabel();
        });
      }
      if (!_rolesReady.isCompleted) _rolesReady.complete();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (!_rolesReady.isCompleted) _rolesReady.complete();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadExistingPlanData() {
    final plan = widget.existingPlan!;
    _planId = plan.id;
    _studentInfo = Map<String, dynamic>.from(plan.studentInfo);
    if ((plan.creatorName.isEmpty || plan.creatorName == 'Kullanıcı') &&
        _userName.isNotEmpty &&
        _userName != 'Yükleniyor...' &&
        _userName != 'Kullanıcı') {
      FirebaseFirestore.instance
          .collection('assessment_action_plans')
          .doc(plan.id)
          .update({'creatorName': _userName})
          .catchError((_) {});
    }
    setState(() {
      _selectedExamIds = Set.from(plan.selectedExamIds);
      _subjectThresholds = Map.from(plan.subjectThresholds);
      _branchActionPlans = Map.from(plan.branchActionPlans);
      
      // Load student tasks and parent notifications
      _studentTasks = {};
      plan.studentTasks.forEach((k, v) {
        if (v is List) {
          _studentTasks[k] = List<Map<String, dynamic>>.from(
            v.map((item) => Map<String, dynamic>.from(item as Map)),
          );
        }
      });
      _parentNotified = Map<String, bool>.from(plan.parentNotified);
      _studentStatus = Map<String, String>.from(plan.studentStatus);

      _selectedClassLevel = plan.classLevel;
      _calculateStats();
    });
  }

  void _loadInitialParameters() {
    setState(() {
      _selectedExamIds = Set.from(widget.initialExamIds!);
      _subjectThresholds = Map.from(widget.initialThresholds!);
      _globalThreshold = widget.initialGlobalThreshold ?? 70.0;
      _selectedClassLevel = widget.initialClassLevel;
      _calculateStats();
    });
  }

  // ───────────────────────── AUTO SAVE ─────────────────────────

  bool get _canAutoSave => widget.existingPlan != null || _userRole != 'teacher';

  Future<String?> _ensurePlanId() async {
    if (_planId != null) return _planId;
    if (_selectedExamIds.isEmpty) return null;
    _createFuture ??= _createPlanDoc();
    return await _createFuture;
  }

  Future<String?> _createPlanDoc() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final selectedExams = _allExams.where((e) => _selectedExamIds.contains(e.id)).toList();
      String title;
      if (selectedExams.length == 1) {
        title = '${selectedExams.first.name} Eylem Planı';
      } else if (selectedExams.length > 1) {
        title = '${selectedExams.length} Sınav Karma Eylem Planı';
      } else {
        title = '${_selectedClassLevel ?? "Tüm"} Sınıflar Eylem Planı';
      }
      title += ' - ${DateFormat("dd.MM.yyyy").format(DateTime.now())}';

      final plan = AssessmentActionPlan(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        title: title,
        date: DateTime.now(),
        createdBy: user?.uid ?? 'anon',
        creatorName: _userName,
        selectedExamIds: _selectedExamIds.toList(),
        selectedExamNames: selectedExams.map((e) => e.name).toList(),
        classLevel: _selectedClassLevel ?? 'Tümü',
        subjectThresholds: _subjectThresholds,
        outcomeStats: _outcomeStats,
        branchActionPlans: _branchActionPlans,
        studentTasks: _studentTasks,
        parentNotified: _parentNotified,
        studentStatus: _studentStatus,
        studentInfo: _studentInfo,
      );
      final id = await _service.saveAssessmentActionPlan(plan);
      _planId = id;
      return id;
    } catch (e) {
      _createFuture = null;
      _showSaveError(e);
      return null;
    }
  }

  void _showSaveError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Otomatik kayıt başarısız: $e'), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _persist(Map<List<String>, dynamic> Function() buildFields) async {
    if (!_canAutoSave) return;
    if (mounted) setState(() => _isAutoSaving = true);
    try {
      final id = await _ensurePlanId();
      if (id == null) return;
      await _service.updateActionPlanFields(id, buildFields());
      if (mounted) setState(() => _lastSaved = DateTime.now());
    } catch (e) {
      _showSaveError(e);
    } finally {
      if (mounted) setState(() => _isAutoSaving = false);
    }
  }

  /// Persists a single branch/outcome action plan entry.
  void _persistBranchPlan(String key) {
    final p = _branchActionPlans[key];
    if (p == null) return;
    setState(() {
      // Once an action is defined and saved, the plan moves to "Uygulanıyor".
      if (p['status'] == 'Eylem Planı Hazır') p['status'] = 'Uygulanıyor';
      p['updatedBy'] = _userName;
      p['updatedByRole'] = _userRole ?? '';
      p['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    });
    _persist(() => {
          ['branchActionPlans', key]: Map<String, dynamic>.from(p),
        });
  }

  Map<String, dynamic>? _resolveStudentInfoFromStats(String key) {
    for (final b in _studentSubjectStats.keys) {
      if (!key.startsWith('${b}_')) continue;
      final subjMap = _studentSubjectStats[b]!;
      for (final s in subjMap.keys) {
        final prefix = '${b}_${s}_';
        if (key.startsWith(prefix)) {
          final id = key.substring(prefix.length);
          final data = subjMap[s]?[id];
          if (data != null) {
            final rate = _studentRate(data);
            return <String, dynamic>{
              'name': (data['name'] ?? '').toString(),
              'no': (data['no'] ?? '').toString(),
              'branch': b,
              'subject': s,
              'success': double.parse(rate.toStringAsFixed(1)),
            };
          }
        }
      }
    }
    return null;
  }

  /// Persists tasks / parent notification of a single student entry.
  void _persistStudent(String key) {
    if (_studentInfo[key] is! Map) {
      final resolved = _resolveStudentInfoFromStats(key);
      if (resolved != null) {
        _studentInfo[key] = resolved;
      }
    }
    final info = _studentInfo[key];
    if (info is Map) {
      String actor = _userName;
      final b = (info['branch'] ?? '').toString();
      final s = (info['subject'] ?? '').toString();
      if (b.isNotEmpty && s.isNotEmpty) {
        final t = _getTeacherName(b, s);
        if (t.isNotEmpty && t != 'Öğretmen Atanmamış') {
          actor = t;
        }
      }
      info['updatedBy'] = actor;
      info['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    _persist(() => {
          ['studentTasks', key]: _studentTasks[key] ?? <Map<String, dynamic>>[],
          ['parentNotified', key]: _parentNotified[key] ?? false,
          if (info != null) ['studentInfo', key]: info,
        });
  }

  /// Öğrencinin ders (branş) başarısı (%): Performans Özeti ile aynı şekilde
  /// NET bazlıdır: net / (doğru + yanlış + boş), 0..100 aralığında.
  double _studentRate(Map data) {
    final netTotal = (data['netTotal'] ?? 0) as num;
    if (netTotal <= 0) return 0.0;
    final net = (data['net'] ?? 0) as num;
    return ((net / netTotal).clamp(0.0, 1.0).toDouble()) * 100;
  }

  /// Performans Özeti ile aynı risk kuralı: şube+ders başarı ortalamasının
  /// %20 ve daha fazla altında kalan öğrenciler riskli sayılır.
  /// Dönen değer risk sınırıdır (başarı %); ortalama 0 ise null.
  double? _riskCutoff(Map students) {
    double sum = 0;
    int count = 0;
    students.forEach((_, data) {
      sum += _studentRate(data);
      count++;
    });
    if (count == 0) return null;
    final avg = sum / count;
    if (avg <= 0) return null;
    return avg * 0.8;
  }

  /// Builds the list of risky students (used for names in reports), plus any
  /// non-critical students that were assigned tasks or parent notifications.
  Map<String, dynamic> _computeStudentInfo() {
    final Map<String, dynamic> result = {};
    _studentSubjectStats.forEach((branch, subjects) {
      subjects.forEach((subject, students) {
        final cutoff = _riskCutoff(students);
        students.forEach((id, data) {
          final s = _studentRate(data);
          final key = '${branch}_${subject}_$id';
          final name = (data['name'] ?? '').toString().trim();
          final nameKey = name.isNotEmpty ? '${branch}_${subject}_$name' : '';

          // Eski kayıtlarda öğrenci numarası yerine öğrenci adıyla kaydedilmiş görev/bildirim varsa birleştir
          if (nameKey.isNotEmpty && nameKey != key) {
            if (_studentTasks.containsKey(nameKey)) {
              final existing = _studentTasks.putIfAbsent(key, () => []);
              for (final t in _studentTasks[nameKey]!) {
                if (!existing.any((et) => et['type'] == t['type'] && et['label'] == t['label'])) {
                  existing.add(t);
                }
              }
              _studentTasks.remove(nameKey);
            }
            if (_parentNotified[nameKey] == true) {
              _parentNotified[key] = true;
              _parentNotified.remove(nameKey);
            }
            if (_studentInfo[nameKey] is Map && _studentInfo[key] is! Map) {
              _studentInfo[key] = _studentInfo[nameKey];
              _studentInfo.remove(nameKey);
            }
          }

          final hasRecord = (_studentTasks[key] ?? const []).isNotEmpty ||
              _parentNotified[key] == true;
          if ((cutoff != null && s <= cutoff) || hasRecord) {
            final assignedTeacher = _getTeacherName(branch, subject);
            result[key] = <String, dynamic>{
              'name': name,
              'no': (data['no'] ?? '').toString(),
              'branch': branch,
              'subject': subject,
              'success': double.parse(s.toStringAsFixed(1)),
              if (hasRecord && assignedTeacher.isNotEmpty && assignedTeacher != 'Öğretmen Atanmamış')
                'updatedBy': assignedTeacher,
            };
          }
        });
      });
    });
    return result;
  }

  /// Existing plans created before reports existed have no student names; fill them once.
  /// Also prunes stale normal-class or old 'Kur' studentInfo keys that are no longer valid.
  void _syncStudentInfo() {
    final computed = _computeStudentInfo();
    if (computed.isEmpty && _outcomeStats.isEmpty) return;
    final merged = <String, dynamic>{...computed};
    _studentInfo.forEach((k, v) {
      if (merged.containsKey(k) && v is Map) {
        final prev = Map<String, dynamic>.from(v);
        final cur = Map<String, dynamic>.from(merged[k] as Map);
        if (cur['updatedBy'] == null && prev['updatedBy'] != null) {
          cur['updatedBy'] = prev['updatedBy'];
        }
        if (prev['updatedAt'] != null) cur['updatedAt'] = prev['updatedAt'];
        merged[k] = cur;
      }
    });
    _studentInfo = merged;
  }

  /// Cleans up stale course-lesson entries in _branchActionPlans, _studentTasks,
  /// _parentNotified, and _studentStatus that were recorded under normal-class
  /// calculations (e.g., 701_İngilizce when Course 701 actually has >= threshold success)
  /// or old 'Kur' / '•' branch keys.
  void _cleanStaleCourseRecords(
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> branchStats,
  ) {
    if (_tracks.isEmpty) return;

    // 1. Clean _branchActionPlans for course subjects
    final newBap = <String, Map<String, dynamic>>{};
    _branchActionPlans.forEach((k, val) {
      final v = Map<String, dynamic>.from(val);
      String matchedBranch = '';
      String matchedSubj = '';
      String matchedOutcome = '';

      for (final s in _availableSubjects) {
        final idx = k.indexOf('_${s}_');
        if (idx > 0) {
          matchedBranch = k.substring(0, idx).trim();
          matchedSubj = s;
          matchedOutcome = k.substring(idx + s.length + 2);
          break;
        }
      }
      if (matchedSubj.isEmpty) {
        newBap[k] = v;
        return;
      }
      final isCourse = _tracks.hasTrackForBranchOrLevel(
        matchedSubj,
        rawBranch: matchedBranch,
        classLevel: _selectedClassLevel,
      );
      if (!isCourse) {
        newBap[k] = v;
        return;
      }
      // Normalize branch name ('701 Kur' -> '701', '... • 704' -> '704')
      String cleanBranch = matchedBranch;
      if (cleanBranch.contains('•')) {
        cleanBranch = cleanBranch.split('•').last.trim();
      }
      if (cleanBranch.endsWith(' Kur')) {
        cleanBranch = cleanBranch.substring(0, cleanBranch.length - 4).trim();
      }
      final outcomeData = branchStats[cleanBranch]?[matchedSubj]?[matchedOutcome];
      if (outcomeData == null) return;
      final total = (outcomeData['total'] ?? 0) as num;
      final correct = (outcomeData['correct'] ?? 0) as num;
      final success = total > 0 ? (correct / total) * 100.0 : 0.0;
      final threshold = _subjectThresholds[matchedSubj] ?? _globalThreshold;
      // Drop stale normal-class entries where the course group outcome is NOT critical
      if (success >= threshold) return;

      final cleanKey = '${cleanBranch}_${matchedSubj}_$matchedOutcome';
      newBap[cleanKey] = v;
    });
    _branchActionPlans = newBap;

    // 2. Clean _studentTasks, _parentNotified, _studentStatus for course subjects
    bool isValidStudentCourseKey(String k) {
      for (final s in _availableSubjects) {
        final idx = k.indexOf('_${s}_');
        if (idx > 0) {
          final b = k.substring(0, idx).trim();
          final isCourse = _tracks.hasTrackForBranchOrLevel(
            s,
            rawBranch: b,
            classLevel: _selectedClassLevel,
          );
          if (!isCourse) return true;
          return _studentInfo.containsKey(k);
        }
      }
      return true;
    }

    _studentTasks.removeWhere((k, v) => v.isEmpty || !isValidStudentCourseKey(k));
    _parentNotified.removeWhere((k, v) => v != true || !isValidStudentCourseKey(k));
    _studentStatus.removeWhere((k, _) => !isValidStudentCourseKey(k));
  }

  /// For existing plans, pre-select branches / subjects that already have valid critical records
  /// so that every saved entry is visible when the plan is reopened.
  void _selectRecordedViews() {
    final plan = widget.existingPlan;
    if (plan == null) return;
    final branches = <String>{};
    final subjects = <String>{};

    _branchActionPlans.forEach((key, v) {
      if ((v['problemSource'] ?? '').toString().trim().isEmpty &&
          (v['actionPlan'] ?? '').toString().trim().isEmpty) {
        return;
      }
      for (final b in _outcomeStats.keys) {
        if (!key.startsWith('${b}_')) continue;
        for (final s in _availableSubjects) {
          final prefix = '${b}_${s}_';
          if (key.startsWith(prefix)) {
            final outcome = key.substring(prefix.length);
            final od = _outcomeStats[b]?[s]?[outcome];
            if (od != null) {
              final total = (od['total'] ?? 0) as num;
              final correct = (od['correct'] ?? 0) as num;
              final success = total > 0 ? (correct / total) * 100.0 : 0.0;
              final threshold = _subjectThresholds[s] ?? _globalThreshold;
              if (success < threshold || !_showOnlyCritical) {
                branches.add(b);
                subjects.add(s);
              }
            }
          }
        }
      }
    });

    void scanStudentKey(String key) {
      if (!_studentInfo.containsKey(key)) return;
      for (final b in _outcomeStats.keys) {
        if (!key.startsWith('${b}_')) continue;
        for (final s in _availableSubjects) {
          if (key.startsWith('${b}_${s}_')) {
            branches.add(b);
            subjects.add(s);
          }
        }
      }
    }

    _studentTasks.forEach((k, v) {
      if (v.isNotEmpty) scanStudentKey(k);
    });
    _parentNotified.forEach((k, v) {
      if (v == true) scanStudentKey(k);
    });

    _selectedViewBranches = branches.isNotEmpty
        ? (_outcomeStats.keys.where(branches.contains).toList()..sort())
        : (_outcomeStats.keys.toList()..sort());
    _selectedViewSubjects = subjects.isNotEmpty
        ? _availableSubjects.where(subjects.contains).toList()
        : List<String>.from(_availableSubjects);
  }

  Future<List<String>> _getOrderedSubjects() async {
    if (_selectedExamIds.isEmpty) return [];
    try {
      final firstExamId = _selectedExamIds.first;
      final exam = _allExams.firstWhere((e) => e.id == firstExamId);
      final examType = await _service.getExamType(exam.examTypeId);
      if (examType != null) {
        return examType.subjects.map((s) => s.branchName).toList();
      }
    } catch (e) {
      debugPrint('Error ordering subjects: $e');
    }
    return _availableSubjects;
  }

  void _filterExams() {
    setState(() {
      _filteredExams = _allExams.where((exam) {
        final matchesClass = _selectedClassLevel == null ||
            exam.classLevel == _selectedClassLevel;
        final matchesSearch = exam.name.toLowerCase().contains(_searchQuery);
        return matchesClass && matchesSearch;
      }).toList();
      _filteredExams.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  void _onExamSelected(String examId) {
    setState(() {
      if (_selectedExamIds.contains(examId)) {
        _selectedExamIds.remove(examId);
      } else {
        _selectedExamIds.add(examId);
      }
    });
    _calculateStats();
  }

  Future<void> _calculateStats() async {
    if (_selectedExamIds.isEmpty) {
      setState(() {
        _outcomeStats = {};
        _availableSubjects = [];
      });
      return;
    }

    setState(() => _isProcessing = true);

    List<TrialExam> selectedExams = _allExams
        .where((e) => _selectedExamIds.contains(e.id))
        .toList();

    // Map<Branch, Map<Subject, Map<Outcome, Map<String, dynamic>>>>
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> branchStats = {};
    // Map<Branch, Map<Subject, Map<StudentKey, Map<String, dynamic>>>>
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> studentSubjStats = {};
    Set<String> subjects = {};

    for (var exam in selectedExams) {
      if (exam.resultsJson == null || exam.resultsJson!.isEmpty) continue;

      try {
        final List<dynamic> results = jsonDecode(exam.resultsJson!);
        
        for (var result in results) {
          final String rawBranch = (result['branch'] ?? result['className'] ?? 'Belirsiz').toString();
          
          Map<String, dynamic> studentSubjects = result['subjects'] ?? {};
          
          studentSubjects.forEach((subjName, subjData) {
            // 1. Determine initial Booklet
            String booklet = (result['booklet'] ?? result['kitapçık'] ?? 'A').toString().toUpperCase().trim();
            if (booklet.isEmpty) booklet = 'A';
            if (!exam.outcomes.containsKey(booklet)) {
              if (exam.outcomes.isNotEmpty) booklet = exam.outcomes.keys.first;
            }

            // 2. Normalize subject name for matching
            String normalizedSubjName = subjName;
            final outcomeSearchMap = exam.outcomes[booklet] ??
                (exam.outcomes.isNotEmpty ? exam.outcomes.values.first : null);
            if (outcomeSearchMap != null && !outcomeSearchMap.containsKey(subjName)) {
              final foundKey = outcomeSearchMap.keys.firstWhere(
                (k) => k.toLowerCase().trim() == subjName.toLowerCase().trim() || 
                       k.toLowerCase().contains(subjName.toLowerCase().trim()) || 
                       subjName.toLowerCase().trim().contains(k.toLowerCase().trim()),
                orElse: () => '',
              );
              if (foundKey.isNotEmpty) normalizedSubjName = foundKey;
            }

            // 2b. Multi-session exams: resolve exact per-subject booklet via student's correctAnswers
            dynamic studentCorrectRaw;
            if (subjData is Map) {
              studentCorrectRaw = subjData['correctAnswers'] ?? subjData['cevapAnahtari'];
            }
            if (studentCorrectRaw == null && result['correctAnswers'] is Map) {
              studentCorrectRaw = result['correctAnswers'][subjName] ?? result['correctAnswers'][normalizedSubjName];
            }
            if (studentCorrectRaw != null) {
              final targetStr = studentCorrectRaw.toString().toUpperCase().trim();
              if (targetStr.isNotEmpty && exam.answerKeys.isNotEmpty) {
                final currentKeyStr = (exam.answerKeys[booklet]?[normalizedSubjName] ?? '').toString().toUpperCase().trim();
                if (currentKeyStr != targetStr) {
                  for (final bk in exam.answerKeys.keys) {
                    final bkKeyStr = (exam.answerKeys[bk]?[normalizedSubjName] ?? '').toString().toUpperCase().trim();
                    if (bkKeyStr == targetStr && exam.outcomes.containsKey(bk)) {
                      booklet = bk;
                      break;
                    }
                  }
                }
              }
            }

            subjects.add(normalizedSubjName);

            // 3. Get Exam Data (Outcomes & Keys)
            var examOutcomes = exam.outcomes[booklet]?[normalizedSubjName];
            var examAnswers = exam.answerKeys[booklet]?[normalizedSubjName];
            
            if (examOutcomes == null || examAnswers == null) return;

            // 4. Extract Student Answers (Robust approach)
            dynamic studentAnsRaw;
            
            // Try subjData first
            if (subjData is Map) {
              studentAnsRaw = subjData['answers'] ?? subjData['cevaplar'] ?? subjData['cevap_anahtari'];
            }
            
            // Try root-level maps if still null
            if (studentAnsRaw == null) {
              if (result['answers'] is Map) {
                studentAnsRaw = result['answers'][subjName] ?? result['answers'][normalizedSubjName];
              }
              if (studentAnsRaw == null && result['cevaplar'] is Map) {
                studentAnsRaw = result['cevaplar'][subjName] ?? result['cevaplar'][normalizedSubjName];
              }
            }
            
            // If still null, try if subjData itself is the string/list
            if (studentAnsRaw == null && (subjData is String || subjData is List)) {
              studentAnsRaw = subjData;
            }

            if (studentAnsRaw == null) return;

            // 5. Parse and Compare
            final studentAnsList = _parseAnswers(studentAnsRaw, examOutcomes.length);
            final correctAnsList = _parseAnswers(studentCorrectRaw ?? examAnswers, examOutcomes.length);

            // Kurs derslerinde (ör. İngilizce) şube yerine öğrencinin o kurs dersindeki şubesi kullanılır.
            final String? branch = _trackBranchFor(
              result,
              normalizedSubjName,
              rawBranch,
              classLevel: (result['classLevel'] ?? exam.classLevel).toString(),
            );
            if (branch == null || branch.isEmpty) return;

            branchStats.putIfAbsent(branch, () => {});
            branchStats[branch]!.putIfAbsent(normalizedSubjName, () => {});
            
            studentSubjStats.putIfAbsent(branch, () => {});
            studentSubjStats[branch]!.putIfAbsent(normalizedSubjName, () => {});
            
            String studentKey = (result['studentNo'] ?? result['studentNumber'] ?? result['number'] ?? result['name'] ?? 'İsimsiz').toString();
            studentSubjStats[branch]![normalizedSubjName]!.putIfAbsent(studentKey, () => {
              'correct': 0,
              'total': 0,
              'net': 0.0,
              'netTotal': 0,
              'name': result['name'] ?? result['studentName'] ?? 'İsimsiz',
              'no': result['studentNo'] ?? result['studentNumber'] ?? result['number'] ?? '',
            });
            int localCorrect = 0;
            int localTotal = 0;

            for (int i = 0; i < examOutcomes.length; i++) {
              String outcome = examOutcomes[i].toString().trim();
              if (outcome.isEmpty || outcome == 'null') outcome = 'Genel';

              branchStats[branch]![normalizedSubjName]!.putIfAbsent(outcome, () => {
                'correct': 0,
                'total': 0,
                'students': <Map<String, dynamic>>[]
              });

              branchStats[branch]![normalizedSubjName]![outcome]!['total']++;
              studentSubjStats[branch]![normalizedSubjName]![studentKey]!['total']++;
              localTotal++;
              
              bool isCorrect = i < studentAnsList.length && i < correctAnsList.length && 
                              studentAnsList[i].trim() == correctAnsList[i].trim() && 
                              studentAnsList[i].trim().isNotEmpty;
              
              if (isCorrect) {
                branchStats[branch]![normalizedSubjName]![outcome]!['correct']++;
                studentSubjStats[branch]![normalizedSubjName]![studentKey]!['correct']++;
                localCorrect++;
              } else {
                (branchStats[branch]![normalizedSubjName]![outcome]!['students'] as List).add({
                  'name': result['name'] ?? result['studentName'] ?? 'İsimsiz',
                  'no': result['studentNo'] ?? result['studentNumber'] ?? result['number'] ?? '',
                  'isWrong': i < studentAnsList.length && studentAnsList[i].trim().isNotEmpty,
                  'isEmpty': i >= studentAnsList.length || studentAnsList[i].trim().isEmpty,
                });
              }
            }

            // Branş başarısı: sınav sonuçlarındaki NET değerini kullan (Performans Özeti ile aynı).
            final stu = studentSubjStats[branch]![normalizedSubjName]![studentKey]!;
            if (subjData is Map && subjData['net'] != null) {
              final c = (subjData['correct'] ?? 0) as num;
              final w = (subjData['wrong'] ?? 0) as num;
              final e = (subjData['empty'] ?? 0) as num;
              stu['net'] = (stu['net'] as num).toDouble() + (subjData['net'] as num).toDouble();
              stu['netTotal'] = (stu['netTotal'] as num).toInt() + (c + w + e).toInt();
            } else {
              stu['net'] = (stu['net'] as num).toDouble() + localCorrect;
              stu['netTotal'] = (stu['netTotal'] as num).toInt() + localTotal;
            }
          });
        }
      } catch (e) {
        debugPrint('Error processing exam ${exam.id}: $e');
      }
    }

    // Öğretmen sadece kendisine atanan şube + dersleri görsün.
    if (_restrictToMyClasses) {
      branchStats.removeWhere((b, subs) {
        subs.removeWhere((s, _) => !_isMyAssignment(b, s));
        return subs.isEmpty;
      });
      studentSubjStats.removeWhere((b, subs) {
        subs.removeWhere((s, _) => !_isMyAssignment(b, s));
        return subs.isEmpty;
      });
      subjects = {
        for (final subs in branchStats.values) ...subs.keys,
      };
    }

    final orderedSubjects = await _getOrderedSubjects();

    setState(() {
      _outcomeStats = branchStats;
      _studentSubjectStats = studentSubjStats;
      
      // Order available subjects according to ExamType
      List<String> found = subjects.toList();
      _availableSubjects = orderedSubjects.where((s) => found.contains(s)).toList();
      // Add any subjects found in results but not in ExamType (fallback)
      for (var s in found) {
        if (!_availableSubjects.contains(s)) _availableSubjects.add(s);
      }

      for (var s in _availableSubjects) {
        _subjectThresholds.putIfAbsent(s, () => _globalThreshold);
      }
      _syncStudentInfo();
      if (!_restrictToMyClasses) {
        _cleanStaleCourseRecords(branchStats);
      }
      if (widget.existingPlan != null && _selectedViewBranches.isEmpty) {
        _selectRecordedViews();
      }
      if (_selectedViewBranches.isEmpty && _outcomeStats.isNotEmpty) {
        final sorted = _outcomeStats.keys.toList()..sort();
        _selectedViewBranches = [sorted.first];
      }
      if (_selectedViewSubjects.isEmpty && _availableSubjects.isNotEmpty) {
        _selectedViewSubjects = [_availableSubjects.first];
      }
      // Öğretmen için varsayılan: kendi branşı (dersi) ve şubeleri seçili gelsin.
      if (!_teacherDefaultsApplied && _isTeacherRole && _restrictToMyClasses) {
        final myBranches = <String>[];
        final mySubjects = <String>[];
        for (final b in _outcomeStats.keys) {
          for (final s in _availableSubjects) {
            if (_outcomeStats[b]!.containsKey(s) && _isMyAssignment(b, s)) {
              if (!myBranches.contains(b)) myBranches.add(b);
              if (!mySubjects.contains(s)) mySubjects.add(s);
            }
          }
        }
        if (myBranches.isNotEmpty && mySubjects.isNotEmpty) {
          myBranches.sort();
          _selectedViewBranches = myBranches;
          _selectedViewSubjects = _availableSubjects.where(mySubjects.contains).toList();
          _teacherDefaultsApplied = true;
        }
      }
      if (_planId != null && _canAutoSave && !_restrictToMyClasses) {
        _service.updateActionPlanFields(_planId!, {
          ['outcomeStats']: branchStats,
          ['studentInfo']: _studentInfo,
          ['branchActionPlans']: _branchActionPlans,
          ['studentTasks']: _studentTasks,
          ['parentNotified']: _parentNotified,
          ['studentStatus']: _studentStatus,
        }).catchError((e) => debugPrint('Error auto-syncing action plan stats: $e'));
      }
      
      _isProcessing = false;
    });
  }

  List<String> _parseAnswers(dynamic raw, int length) {
    if (raw == null) return List.filled(length, ' ');
    
    List<String> res = [];
    if (raw is List) {
      res = raw.map((e) => e.toString().toUpperCase().trim()).toList();
    } else {
      String s = raw.toString().toUpperCase().trim();
      if (s.contains(' ') || s.contains(',') || s.contains('|')) {
        res = s.split(RegExp(r'[\s,|]')).where((e) => e.isNotEmpty).toList();
        if (res.length != length) {
          res = s.replaceAll(RegExp(r'[,|.]'), '').split('');
          if (res.length > length) {
            res = res.where((e) => e != ' ').toList();
          }
        }
      } else {
        res = s.split('');
      }
    }

    if (res.length > length) {
      res = res.sublist(0, length);
    } else if (res.length < length) {
      res.addAll(List.filled(length - res.length, ' '));
    }
    
    return res.map((e) => e.isEmpty ? ' ' : e).toList();
  }

  void _applyGlobalThreshold(double val) {
    setState(() {
      _globalThreshold = val;
      for (var s in _availableSubjects) {
        _subjectThresholds[s] = val;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: EduknAppBar(
        title: 'Eylem Planları',
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Tooltip(
                  message: _isAutoSaving
                      ? 'Kaydediliyor...'
                      : (_lastSaved != null ? 'Değişiklikler otomatik kaydedildi' : 'Değişiklikler otomatik kaydedilir'),
                  child: _isAutoSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo.shade400),
                        )
                      : Icon(
                          _lastSaved != null ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                          color: _lastSaved != null ? Colors.green.shade600 : Colors.indigo.shade200,
                          size: 22,
                        ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.indigo.shade700,
          indicatorWeight: 4,
          labelColor: Colors.indigo.shade900,
          unselectedLabelColor: Colors.indigo.shade300,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'ŞUBE EYLEM PLANI'),
            Tab(text: 'ÖĞRENCİ TAKİBİ'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: EduKnLoader(size: 80))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStep2BranchPlans(),
                _buildStep3StudentPlans(),
              ],
            ),
    );
  }


  Widget _buildStep2BranchPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                _buildHeader('Şube Eylem Planları', 'Düşük başarı gösterilen kazanımlar için eylem planı belirleyin.'),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildFilterToggle(true),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMultiSelectFilter('Şube', _selectedViewBranches, _branchFilterOptions, (v) => setState(() => _selectedViewBranches = v), Icons.business)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() {
                      _selectedViewSubjects = v;
                      final opts = _branchFilterOptions;
                      _selectedViewBranches = _selectedViewBranches.where(opts.contains).toList();
                      if (_selectedViewBranches.isEmpty && opts.isNotEmpty) {
                        _selectedViewBranches = [opts.first];
                      }
                    }), Icons.book)),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: _buildHeader('Şube Eylem Planları', 'Düşük başarı gösterilen kazanımlar için eylem planı belirleyin.')),
                    _buildFilterToggle(false),
                    const SizedBox(width: 16),
                    _buildMultiSelectFilter('Şube', _selectedViewBranches, _branchFilterOptions, (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
                    const SizedBox(width: 12),
                    _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() {
                      _selectedViewSubjects = v;
                      final opts = _branchFilterOptions;
                      _selectedViewBranches = _selectedViewBranches.where(opts.contains).toList();
                      if (_selectedViewBranches.isEmpty && opts.isNotEmpty) {
                        _selectedViewBranches = [opts.first];
                      }
                    }), Icons.book, width: 200),
                  ],
                ),
              const SizedBox(height: 32),
              _buildMultiFilteredOutcomeTable(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterToggle(bool isMobile) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _showOnlyCritical = !_showOnlyCritical),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 12),
        decoration: BoxDecoration(
          color: _showOnlyCritical ? Colors.red.shade50 : Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _showOnlyCritical ? Colors.red.shade200 : Colors.indigo.shade200),
          boxShadow: [
            BoxShadow(
              color: (_showOnlyCritical ? Colors.red : Colors.indigo).withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _showOnlyCritical ? Icons.report_problem_rounded : Icons.view_list_rounded,
              color: _showOnlyCritical ? Colors.red.shade700 : Colors.indigo.shade700,
              size: 18,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Text(
                _showOnlyCritical ? 'Sadece Kritikler' : 'Tüm Kazanımlar',
                style: TextStyle(
                  color: _showOnlyCritical ? Colors.red.shade900 : Colors.indigo.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentFilterToggle(bool isMobile) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _showOnlyCriticalStudents = !_showOnlyCriticalStudents),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 12),
        decoration: BoxDecoration(
          color: _showOnlyCriticalStudents ? Colors.red.shade50 : Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _showOnlyCriticalStudents ? Colors.red.shade200 : Colors.indigo.shade200),
          boxShadow: [
            BoxShadow(
              color: (_showOnlyCriticalStudents ? Colors.red : Colors.indigo).withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _showOnlyCriticalStudents ? Icons.report_problem_rounded : Icons.view_list_rounded,
              color: _showOnlyCriticalStudents ? Colors.red.shade700 : Colors.indigo.shade700,
              size: 18,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Text(
                _showOnlyCriticalStudents ? 'Sadece Kritikler' : 'Tüm Öğrenciler',
                style: TextStyle(
                  color: _showOnlyCriticalStudents ? Colors.red.shade900 : Colors.indigo.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Şube filtresi seçenekleri: sadece seçili derslerde verisi olan şubeler/kurlar.
  /// Böylece kur etiketleri (ör. İngilizce kurları) yalnızca kur dersi seçiliyken görünür.
  List<String> get _branchFilterOptions {
    final all = <String>{..._outcomeStats.keys, ..._studentSubjectStats.keys}.toList()..sort();
    if (_selectedViewSubjects.isEmpty) return all;
    return all
        .where((b) => _selectedViewSubjects.any((s) =>
            (_outcomeStats[b]?[s] ?? const {}).isNotEmpty ||
            (_studentSubjectStats[b]?[s] ?? const {}).isNotEmpty))
        .toList();
  }

  Widget _buildMultiFilteredOutcomeTable() {
    List<Widget> cards = [];
    for (var branch in _selectedViewBranches) {
      for (var subject in _selectedViewSubjects) {
        final outcomesMap = _outcomeStats[branch]?[subject] ?? {};
        final threshold = _subjectThresholds[subject] ?? 70.0;
        final sorted = outcomesMap.entries.toList()..sort((a, b) {
          double sA = a.value['total'] > 0 ? (a.value['correct'] / a.value['total']) * 100 : 0;
          double sB = b.value['total'] > 0 ? (b.value['correct'] / b.value['total']) * 100 : 0;
          return sA.compareTo(sB);
        });
        if (sorted.isEmpty) continue;
        
        final filteredRows = sorted.where((e) {
          if (!_showOnlyCritical) return true;
          double success = e.value['total'] > 0 ? (e.value['correct'] / e.value['total']) * 100 : 0;
          return success < threshold;
        }).toList();

        if (filteredRows.isEmpty) continue;

        final bool isCourse = _tracks.hasTrackForBranchOrLevel(
          subject,
          rawBranch: branch,
          classLevel: _selectedClassLevel,
        );
        final int studentCount = (_studentSubjectStats[branch]?[subject] ?? const {}).length;

        cards.add(Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(branch, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)), backgroundColor: Colors.indigo.shade900),
                  Text(subject, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (isCourse)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.deepPurple.shade200),
                      ),
                      child: Text(
                        'Kurs Şubesi ($studentCount Öğrenci)',
                        style: TextStyle(
                          color: Colors.deepPurple.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...filteredRows.map((e) => _buildOutcomeRow(branch, subject, e.key, e.value, threshold)).toList(),
            ],
          ),
        ));
      }
    }
    return cards.isEmpty ? _buildEmptyState(_showOnlyCritical ? 'Kritik başarı seviyesinde kazanım bulunamadı.' : 'Veri bulunamadı.') : Column(children: cards);
  }

  Widget _buildOutcomeRow(String branch, String subject, String outcome, Map<String, dynamic> data, double threshold) {
    double success = data['total'] > 0 ? (data['correct'] / data['total']) * 100 : 0.0;
    bool isLow = success < threshold;
    String key = '${branch}_${subject}_$outcome';
    if (!_branchActionPlans.containsKey(key)) {
      final baseBranch = branch.endsWith(' Kur') ? branch.substring(0, branch.length - 4).trim() : '$branch Kur';
      final altKey = '${baseBranch}_${subject}_$outcome';
      if (_branchActionPlans.containsKey(altKey)) {
        _branchActionPlans[key] = Map<String, dynamic>.from(_branchActionPlans[altKey]!);
      }
    }
    _branchActionPlans.putIfAbsent(key, () => {'problemSource': '', 'actionPlan': '', 'status': 'Belirlenmedi'});
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 700;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isLow ? Colors.red.shade100 : Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: (isLow ? Colors.red : Colors.indigo).withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isLow ? Colors.red.shade50.withValues(alpha: 0.3) : Colors.indigo.shade50.withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isLow ? Colors.red.shade100 : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isLow ? 'KRİTİK' : 'YETERLİ',
                                  style: TextStyle(
                                    color: isLow ? Colors.red.shade900 : Colors.green.shade900,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '%${success.toStringAsFixed(1)} Başarı',
                                style: TextStyle(
                                  color: isLow ? Colors.red.shade700 : Colors.indigo.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            outcome,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildTeacherBadge(branch, subject),
                  ],
                ),
              ),
              
              // Inputs Section
              Padding(
                padding: const EdgeInsets.all(20),
                child: isMobile 
                  ? Column(
                      children: [
                        _buildPremiumInputCard('Problem Kaynağı', _buildProblemSourceDropdown(key), Icons.psychology_outlined),
                        const SizedBox(height: 16),
                        _buildPremiumInputCard('Eylem Planı', _buildActionPlanField(key), Icons.assignment_outlined),
                        const SizedBox(height: 16),
                        _buildPremiumInputCard('Durum', _buildStatusBadge(key), Icons.flag_outlined, noPadding: true),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildPremiumInputCard('Problem Kaynağı', _buildProblemSourceDropdown(key), Icons.psychology_outlined)),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: _buildPremiumInputCard('Eylem Planı', _buildActionPlanField(key), Icons.assignment_outlined)),
                        const SizedBox(width: 16),
                        SizedBox(width: 160, child: _buildPremiumInputCard('Durum', _buildStatusBadge(key), Icons.flag_outlined, noPadding: true)),
                      ],
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeacherBadge(String branch, String subject) {
    String teacher = _getTeacherName(branch, subject);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.indigo.shade100,
            child: Text(teacher[0], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
          ),
          const SizedBox(width: 8),
          Text(_trackSlotFor(branch, subject) != null ? '$teacher • Kur' : teacher, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPremiumInputCard(String label, Widget child, IconData icon, {bool noPadding = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.indigo.shade400),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade900.withValues(alpha: 0.6))),
            ],
          ),
        ),
        Container(
          height: 48,
          alignment: Alignment.centerLeft,
          padding: noPadding ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.shade50.withValues(alpha: 0.8), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: noPadding 
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14.8), // Adjusted for border width
                  child: SizedBox.expand(child: child),
                ) 
              : child,
        ),
      ],
    );
  }

  // ── Öğrenci takibi: performans önbelleği ──
  // Hesaplama (risk sınırı, filtre, sıralama) her setState'te tekrar yapılmasın diye
  // istatistik/filtre değişmedikçe önbellekten döner.
  Object? _groupsCacheStats;
  String _groupsCacheSig = '';
  List<_StudentGroup> _groupsCache = const [];
  final Set<String> _collapsedGroups = {};

  List<_StudentGroup> _studentGroups() {
    final sig = '$_showOnlyCriticalStudents|${_selectedViewBranches.join(',')}|'
        '${_selectedViewSubjects.join(',')}|$_selectedClassLevel';
    if (identical(_groupsCacheStats, _studentSubjectStats) && _groupsCacheSig == sig) {
      return _groupsCache;
    }
    final groups = <_StudentGroup>[];
    for (var branch in _selectedViewBranches) {
      for (var subject in _selectedViewSubjects) {
        final studentsMap = _studentSubjectStats[branch]?[subject] ?? {};
        if (studentsMap.isEmpty) continue;
        final cutoff = _riskCutoff(studentsMap);
        final List<Map<String, dynamic>> filtered = [];
        studentsMap.forEach((id, data) {
          final double s = _studentRate(data);
          final bool isCritical = cutoff != null && s <= cutoff;
          if (!_showOnlyCriticalStudents || isCritical) {
            filtered.add({...data, 'success': s, 'id': id, 'isCritical': isCritical});
          }
        });
        if (filtered.isEmpty) continue;
        filtered.sort((a, b) => (a['success'] as double).compareTo(b['success'] as double));
        groups.add(_StudentGroup(
          branch: branch,
          subject: subject,
          students: filtered,
          criticalCount: filtered.where((s) => s['isCritical'] == true).length,
          isCourse: _tracks.hasTrackForBranchOrLevel(
            subject,
            rawBranch: branch,
            classLevel: _selectedClassLevel,
          ),
        ));
      }
    }
    _groupsCacheStats = _studentSubjectStats;
    _groupsCacheSig = sig;
    _groupsCache = groups;
    return groups;
  }

  Widget _buildStep3StudentPlans() {
    if (_selectedExamIds.isEmpty) return _buildEmptyState('Lütfen önce sınav seçimi yapın.');

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 700;
        final groups = _studentGroups();

        // Açık gruplar için düz (flat) liste: başlık + öğrenci satırları.
        // SliverList.builder sayesinde yalnızca ekranda görünen satırlar oluşturulur.
        final List<Object> items = [];
        for (final g in groups) {
          items.add(g);
          if (_collapsedGroups.contains(g.key)) continue;
          for (var i = 0; i < g.students.length; i++) {
            items.add(_StudentEntry(g, g.students[i], i == g.students.length - 1));
          }
        }

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              _buildHeader('Öğrenci Takibi', 'Şube ve ders bazında sınıf ortalamasının %20 altında kalan riskli öğrenciler.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildStudentFilterToggle(true),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMultiSelectFilter('Şube', _selectedViewBranches, _branchFilterOptions, (v) => setState(() => _selectedViewBranches = v), Icons.business)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() {
                    _selectedViewSubjects = v;
                    final opts = _branchFilterOptions;
                    _selectedViewBranches = _selectedViewBranches.where(opts.contains).toList();
                    if (_selectedViewBranches.isEmpty && opts.isNotEmpty) {
                      _selectedViewBranches = [opts.first];
                    }
                  }), Icons.book)),
                ],
              ),
            ] else
              Row(
                children: [
                  Expanded(child: _buildHeader('Öğrenci Takibi', 'Şube ve ders bazında sınıf ortalamasının %20 altında kalan riskli öğrenciler.')),
                  _buildStudentFilterToggle(false),
                  const SizedBox(width: 16),
                  _buildMultiSelectFilter('Şube', _selectedViewBranches, _branchFilterOptions, (v) => setState(() => _selectedViewBranches = v), Icons.business, width: 180),
                  const SizedBox(width: 12),
                  _buildMultiSelectFilter('Branş', _selectedViewSubjects, _availableSubjects, (v) => setState(() {
                    _selectedViewSubjects = v;
                    final opts = _branchFilterOptions;
                    _selectedViewBranches = _selectedViewBranches.where(opts.contains).toList();
                    if (_selectedViewBranches.isEmpty && opts.isNotEmpty) {
                      _selectedViewBranches = [opts.first];
                    }
                  }), Icons.book, width: 200),
                ],
              ),
            const SizedBox(height: 32),
          ],
        );

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              sliver: SliverToBoxAdapter(child: header),
            ),
            if (items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                sliver: SliverToBoxAdapter(
                  child: _buildEmptyState(_showOnlyCriticalStudents ? 'Kritik başarı seviyesinde öğrenci bulunamadı.' : 'Öğrenci bulunamadı.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is _StudentGroup) {
                      return _buildStudentGroupHeader(item);
                    }
                    final e = item as _StudentEntry;
                    final g = e.group;
                    final s = e.student;
                    final key = '${g.branch}_${g.subject}_${s['id']}';
                    final baseBranch = g.branch.endsWith(' Kur') ? g.branch.substring(0, g.branch.length - 4).trim() : '${g.branch} Kur';
                    final altKey = '${baseBranch}_${g.subject}_${s['id']}';
                    if (!_studentTasks.containsKey(key) && _studentTasks.containsKey(altKey)) {
                      _studentTasks[key] = _studentTasks[altKey]!;
                    }
                    if (!_parentNotified.containsKey(key) && _parentNotified.containsKey(altKey)) {
                      _parentNotified[key] = _parentNotified[altKey]!;
                    }
                    if (!_studentStatus.containsKey(key) && _studentStatus.containsKey(altKey)) {
                      _studentStatus[key] = _studentStatus[altKey]!;
                    }
                    final isSelected = _selectedStudentKeys.contains(key);
                    final tasks = _studentTasks[key] ?? [];
                    final border = BorderSide(color: Colors.indigo.shade50, width: 1.5);
                    final radius = e.isLast
                        ? const BorderRadius.vertical(bottom: Radius.circular(20))
                        : BorderRadius.zero;
                    return RepaintBoundary(
                      key: ValueKey(key),
                      child: Container(
                        margin: EdgeInsets.only(bottom: e.isLast ? 16 : 0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: radius,
                          border: Border(left: border, right: border, bottom: e.isLast ? border : BorderSide.none),
                        ),
                        child: ClipRRect(
                          borderRadius: radius,
                          child: _buildStudentRow(g.branch, g.subject, s, key, isSelected, tasks),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStudentGroupHeader(_StudentGroup g) {
    final groupKeys = g.students.map((s) => '${g.branch}_${g.subject}_${s['id']}').toList();
    final allSelected = groupKeys.every((k) => _selectedStudentKeys.contains(k));
    final someSelected = groupKeys.any((k) => _selectedStudentKeys.contains(k));
    final collapsed = _collapsedGroups.contains(g.key);
    final count = g.students.length;
    final base = g.isCourse ? 'kurs şubesi ort. -%20' : 'sınıf ort. -%20';
    final subtitle = _showOnlyCriticalStudents
        ? '$count riskli öğrenci ($base)'
        : '$count öğrenci (${g.criticalCount} kritik • $base)';
    final radius = collapsed
        ? BorderRadius.circular(20)
        : const BorderRadius.vertical(top: Radius.circular(20));

    return Container(
      margin: EdgeInsets.only(bottom: collapsed ? 16 : 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(color: Colors.indigo.shade50, width: 1.5),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () => setState(() {
          if (collapsed) {
            _collapsedGroups.remove(g.key);
          } else {
            _collapsedGroups.add(g.key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: allSelected ? true : (someSelected ? null : false),
                tristate: true,
                activeColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (_) {
                  setState(() {
                    if (allSelected) {
                      _selectedStudentKeys.removeAll(groupKeys);
                    } else {
                      _selectedStudentKeys.addAll(groupKeys);
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.isCourse ? '${g.branch} (Kurs Şubesi) — ${g.subject}' : '${g.branch} — ${g.subject}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.indigo, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              if (someSelected) ...[
                const SizedBox(width: 8),
                _buildBulkActionButton(g.branch, g.subject, groupKeys.where((k) => _selectedStudentKeys.contains(k)).toList()),
              ],
              const SizedBox(width: 4),
              Icon(collapsed ? Icons.expand_more : Icons.expand_less, color: Colors.indigo.shade300),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulkActionButton(String branch, String subject, List<String> selectedKeys) {
    return TextButton.icon(
      onPressed: () => _showTaskAssignBottomSheet(keys: selectedKeys),
      icon: const Icon(Icons.playlist_add, size: 16),
      label: Text('${selectedKeys.length} Kişiye Görev', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.indigo,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildStudentRow(String branch, String subject, Map<String, dynamic> s, String key, bool isSelected, List<Map<String, dynamic>> tasks) {
    final notified = _parentNotified[key] ?? false;
    final bool isCritical = s['isCritical'] ?? true;

    // ── Auto-derive status from tasks ──
    final hasTasks = tasks.isNotEmpty;
    final allDone = hasTasks && tasks.every((t) => t['done'] == true);
    final statusLabel = allDone ? 'Tamamlandı' : (hasTasks ? 'Planlandı' : 'Beklemede');
    final statusColor = allDone ? Colors.green : (hasTasks ? Colors.blue : Colors.grey);

    // ── Shared: task badges (kırmızı = atandı/bekliyor, yeşil = takibi yapıldı; tıklayınca değişir) ──
    Widget taskBadges = tasks.isEmpty
        ? const SizedBox.shrink()
        : Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tasks.map((t) {
              final done = t['done'] == true;
              return Tooltip(
                message: done ? 'Takibi yapıldı (geri almak için tıkla)' : 'Takibi yapıldı olarak işaretle',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() => t['done'] = !done);
                    _persistStudent(key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: done ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: done ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (done) ...[
                          Icon(Icons.check_circle, size: 11, color: Colors.green.shade700),
                          const SizedBox(width: 3),
                        ],
                        Text(t['label'], style: TextStyle(
                          fontSize: 10,
                          color: done ? Colors.green.shade800 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        )),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );

    // ── Shared: auto status badge (read-only) ──
    Widget statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor.shade700)),
        ],
      ),
    );

    Widget parentBtn = Tooltip(
      message: notified ? 'Veli bilgilendirildi' : 'Veli bilgilendirmesi yap',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() => _parentNotified[key] = !notified);
          _persistStudent(key);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: notified ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: notified ? Colors.green.shade300 : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                notified ? Icons.family_restroom : Icons.family_restroom_outlined,
                size: 16,
                color: notified ? Colors.green.shade700 : Colors.grey.shade500,
              ),
              const SizedBox(width: 5),
              Text(
                notified ? 'Bilgilendirildi' : 'Veli',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: notified ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
              if (notified) ...[ 
                const SizedBox(width: 4),
                Icon(Icons.check_circle, size: 12, color: Colors.green.shade600),
              ],
            ],
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // ── MOBILE: Card layout ──
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.indigo.shade200 : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: checkbox + avatar + name + success%
                    Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          activeColor: Colors.indigo,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (_) => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
                        ),
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isSelected ? Colors.indigo.shade200 : Colors.indigo.shade100,
                          child: Text(
                            (s['name'] as String? ?? '?').isNotEmpty ? (s['name'] as String)[0] : '?',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isCritical ? Colors.red.shade50 : Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: isCritical ? Colors.red.shade100 : Colors.green.shade200),
                                    ),
                                    child: Text(
                                      '%${(s['success'] as double).toStringAsFixed(1)} Başarı${_showOnlyCriticalStudents ? '' : (isCritical ? ' • KRİTİK' : ' • YETERLİ')}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isCritical ? Colors.red.shade700 : Colors.green.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Görev Ata
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showTaskAssignBottomSheet(keys: [key]),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.indigo.shade100),
                            ),
                            child: Icon(Icons.add_task_rounded, size: 20, color: Colors.indigo.shade700),
                          ),
                        ),
                      ],
                    ),
                    // Task badges
                    if (tasks.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      taskBadges,
                    ],
                    const SizedBox(height: 10),
                    // Bottom row: status badge + parent notification
                    Row(
                      children: [
                        statusBadge,
                        const SizedBox(width: 8),
                        Expanded(child: parentBtn),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // ── DESKTOP: Single row layout ──
        return Material(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: Colors.indigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (_) => setState(() => isSelected ? _selectedStudentKeys.remove(key) : _selectedStudentKeys.add(key)),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.indigo.shade100,
                    child: Text(
                      (s['name'] as String? ?? '?').isNotEmpty ? (s['name'] as String)[0] : '?',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('Başarı: %${(s['success'] as double).toStringAsFixed(1)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            if (!_showOnlyCriticalStudents) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isCritical ? Colors.red.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: isCritical ? Colors.red.shade200 : Colors.green.shade200),
                                ),
                                child: Text(
                                  isCritical ? 'KRİTİK' : 'YETERLİ',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isCritical ? Colors.red.shade700 : Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (tasks.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          taskBadges,
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_task_rounded, size: 20),
                    color: Colors.indigo,
                    tooltip: 'Görev Ata',
                    onPressed: () => _showTaskAssignBottomSheet(keys: [key]),
                  ),
                  statusBadge,
                  const SizedBox(width: 8),
                  parentBtn,
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  void _showTaskAssignBottomSheet({required List<String> keys}) {
    // Mevcut görevleri önceden seçili getir (tüm seçili öğrencilerde ortak olanlar)
    Set<String> initialTypes = keys.isEmpty
        ? {}
        : (_studentTasks[keys.first] ?? []).map((t) => t['type'] as String).toSet();
    for (final k in keys.skip(1)) {
      initialTypes = initialTypes.intersection((_studentTasks[k] ?? []).map((t) => t['type'] as String).toSet());
    }
    final Set<String> selectedTypes = {...initialTypes};
    final bool isEdit = initialTypes.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              Text(
                  isEdit
                      ? (keys.length > 1 ? '${keys.length} Öğrencinin Görevlerini Düzenle' : 'Görevleri Düzenle')
                      : (keys.length > 1 ? '${keys.length} Öğrenciye Görev Ata' : 'Görev Ata'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 8),
              Text('Görev türlerini seçin; seçimi kaldırdığınız görev silinir',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.2,
                physics: const NeverScrollableScrollPhysics(),
                children: _taskTypes.map((t) {
                  final isSelected = selectedTypes.contains(t['type']);
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setSheet(() =>
                        isSelected ? selectedTypes.remove(t['type']) : selectedTypes.add(t['type'] as String)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? Colors.indigo : Colors.indigo.shade100),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t['icon'] as IconData, size: 26,
                              color: isSelected ? Colors.white : Colors.indigo.shade600),
                          const SizedBox(height: 8),
                          Text(t['label'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.indigo.shade900)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (selectedTypes.isEmpty && !isEdit) ? null : () {
                    setState(() {
                      for (final key in keys) {
                        _studentTasks.putIfAbsent(key, () => []);
                        // Düzenleme: seçimi kaldırılan görevleri sil
                        final removed = initialTypes.difference(selectedTypes);
                        _studentTasks[key]!.removeWhere((t) => removed.contains(t['type']));
                        for (final type in selectedTypes) {
                          final taskDef = _taskTypes.firstWhere((t) => t['type'] == type);
                          final alreadyHas = _studentTasks[key]!.any((t) => t['type'] == type);
                          if (!alreadyHas) {
                            _studentTasks[key]!.add({'type': type, 'label': taskDef['label'], 'done': false});
                          }
                        }
                      }
                    });
                    for (final key in keys) {
                      _persistStudent(key);
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    selectedTypes.isEmpty ? 'Görev Seçin' : '${selectedTypes.length} Görevi Ata',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.indigo.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectFilter(String hint, List<String> selected, List<String> all, Function(List<String>) onChanged, IconData icon, {double? width}) {
    bool isAll = selected.length == all.length && all.isNotEmpty;
    bool hasSelection = selected.isNotEmpty;

    return Container(
      width: width,
      height: 44,
      decoration: BoxDecoration(
        color: hasSelection ? Colors.indigo.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasSelection ? Colors.indigo.shade200 : Colors.grey.shade200),
        boxShadow: hasSelection ? [BoxShadow(color: Colors.indigo.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
      ),
      child: MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
        menuChildren: [
          SizedBox(
            width: width ?? 200,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MenuItemButton(
                      closeOnActivate: false,
                      onPressed: () => onChanged(isAll ? [] : List.from(all)),
                      leadingIcon: Icon(
                        isAll ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: Colors.indigo,
                      ),
                      child: const Text('Tümü', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const Divider(height: 1),
                    ...all.map((e) => MenuItemButton(
                          closeOnActivate: false,
                          onPressed: () {
                            final next = List<String>.from(selected);
                            next.contains(e) ? next.remove(e) : next.add(e);
                            onChanged(next);
                          },
                          leadingIcon: Icon(
                            selected.contains(e) ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 20,
                            color: Colors.indigo,
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 13)),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
        builder: (context, controller, _) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: hasSelection ? Colors.indigo.shade700 : Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAll ? 'Tümü' : (hasSelection ? '${selected.length} Seçili' : hint),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                      color: hasSelection ? Colors.indigo.shade900 : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, size: 16, color: hasSelection ? Colors.indigo.shade700 : Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdCard(String subject) {
    double value = _subjectThresholds[subject] ?? 70.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text('%${value.round()}', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: Colors.indigo,
              inactiveColor: Colors.indigo.withValues(alpha: 0.1),
              onChanged: (v) => setState(() => _subjectThresholds[subject] = v),
            ),
          ),
        ],
      ),
    );
  }

  void _showSelectionBottomSheet({
    required String title,
    required List<String> options,
    required String current,
    required Function(String) onSelected,
    String? fieldKey,
  }) {
    bool isManual = fieldKey != null && current.isNotEmpty && !options.contains(current);
    final manualController = TextEditingController(text: isManual ? current : '');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 24),
              if (!isManual)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (c, i) => Divider(color: Colors.grey.shade100, height: 1),
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final isSelected = opt == current;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        title: Text(
                          opt,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.indigo : Colors.black87,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.indigo) : null,
                        onTap: () {
                          if (opt == 'Diğer' && fieldKey != null) {
                            setModalState(() => isManual = true);
                          } else {
                            onSelected(opt);
                            Navigator.pop(context);
                          }
                        },
                      );
                    },
                  ),
                )
              else
                Column(
                  children: [
                    TextField(
                      controller: manualController,
                      autofocus: true,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Eylem planınızı buraya detaylıca yazabilirsiniz...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        filled: false,
                        contentPadding: const EdgeInsets.all(20),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Colors.indigo, width: 2),
                        ),
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => setModalState(() => isManual = false),
                            child: const Text('Geri Dön', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              if (manualController.text.trim().isNotEmpty) {
                                onSelected(manualController.text.trim());
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Kaydet ve Tamamla', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProblemSourceDropdown(String key) {
    final sources = [
      'Kazanım için gerekli olan önceki sınıf/konu bilgileri şubenin çoğunda eksik.',
      'Kazanımın temel kavramları şubenin büyük bir bölümü tarafından yanlış öğrenilmiş veya hatalı yorumlanmıştır.',
      'Kazanılan bilgiyi kullanmaya yönelik yeterli sınıf içi/ek alıştırma yapılmamış.',
      'Kullanılan öğretim yöntemi (anlatım, materyal vb.) şubenin öğrenme stillerine uygun değil.',
      'Sorular çeldiricili, ifade/dil anlaşılırlığı düşük veya zaman yönetimi sorunu var.',
      'Şubenin genelindeki dikkat dağınıklığı veya olumsuz tutumun öğrenmeye yansıması.',
      'Konu yetişmedi.',
      'Müfredat dışı.',
      'Soru anlaşılmadı.',
    ];
    String current = _branchActionPlans[key]?['problemSource'] ?? '';
    
    return InkWell(
      onTap: () => _showSelectionBottomSheet(
        title: 'Problem Kaynağı Seçin',
        options: sources,
        current: current,
        onSelected: (val) {
          setState(() {
            _branchActionPlans[key]!['problemSource'] = val;
            _updateStatus(key);
          });
          _persistBranchPlan(key);
        },
      ),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                current == '' ? 'Seçiniz' : current,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: current == '' ? Colors.grey : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.indigo, size: 18),
          ],
        ),
      ),
    );
  }

  void _updateStatus(String key) {
    final plan = _branchActionPlans[key]!;
    final problem = plan['problemSource'] ?? '';
    final action = plan['actionPlan'] ?? '';
    final currentStatus = plan['status'] ?? 'Belirlenmedi';

    // Auto-update if in early stages
    if (currentStatus == 'Belirlenmedi' || currentStatus == 'Problem Belirlendi' || currentStatus == 'Eylem Planı Hazır') {
      if (action.isNotEmpty && action != ' ') {
        plan['status'] = 'Eylem Planı Hazır';
      } else if (problem.isNotEmpty && problem != ' ') {
        plan['status'] = 'Problem Belirlendi';
      } else {
        plan['status'] = 'Belirlenmedi';
      }
    }
  }

  Widget _buildActionPlanField(String key) {
    String current = _branchActionPlans[key]?['actionPlan'] ?? '';
    bool isOther = current.isNotEmpty && !_predefinedActionPlans.contains(current) && current != ' ';

    return InkWell(
      onTap: () {
        final problem = _branchActionPlans[key]?['problemSource'] ?? '';
        if (problem.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lütfen önce problem kaynağını belirleyin.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _showSelectionBottomSheet(
          title: 'Eylem Planı Seçin',
          options: _predefinedActionPlans,
          current: current,
          fieldKey: key,
          onSelected: (val) {
            setState(() {
              _branchActionPlans[key]!['actionPlan'] = val;
              _updateStatus(key);
            });
            _persistBranchPlan(key);
          },
        );
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                current.isEmpty ? 'Eylem planı seçiniz' : (isOther ? 'Özel: $current' : current),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: current.isEmpty ? Colors.grey : (isOther ? Colors.indigo.shade700 : Colors.black87),
                  fontWeight: isOther ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.indigo, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String key) {
    String current = _branchActionPlans[key]?['status'] ?? 'Belirlenmedi';
    
    final colorMap = {
      'Belirlenmedi': Colors.grey,
      'Problem Belirlendi': Colors.orange,
      'Eylem Planı Hazır': Colors.blue,
      'Uygulanıyor': Colors.indigo,
      'Tamamlandı': Colors.green,
    };
    final color = colorMap[current] ?? Colors.grey;
    final canToggle = current == 'Uygulanıyor' || current == 'Tamamlandı';

    return InkWell(
      onTap: !canToggle ? null : () {
        setState(() {
          _branchActionPlans[key]!['status'] = current == 'Uygulanıyor' ? 'Tamamlandı' : 'Uygulanıyor';
        });
        _persistBranchPlan(key);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                current.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color.shade900,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canToggle) ...[
              const SizedBox(width: 4),
              Icon(Icons.sync_alt_rounded, size: 14, color: color.shade600),
            ],
          ],
        ),
      ),
    );
  }

  String _getTeacherName(String branch, String subject) {
    // 0. Kur ise: Kurs Listesi'ndeki kurun öğretmeni
    final slot = _trackSlotFor(branch, subject);
    if (slot != null) {
      return slot.teacherNames.isNotEmpty ? slot.teacherNames.join(', ') : 'Öğretmen Atanmamış';
    }
    // 1. Exact branch + subject match
    final exact = _branchTeachers[branch]?[subject];
    if (exact != null) return exact;

    // 2. Normalize edilmiş şube + (kısmi eşleşen) ders adı araması
    final b = _normKey(branch);
    final s = _normKey(subject);
    for (final a in _allAssignments) {
      final cl = _normKey(a['lesson'] ?? '');
      if (_normKey(a['cls'] ?? '') == b &&
          cl.isNotEmpty &&
          s.isNotEmpty &&
          (cl == s || cl.contains(s) || s.contains(cl))) {
        return a['teachers'] ?? 'Öğretmen Atanmamış';
      }
    }

    // 3. Try subject-only fallback (for general accounts where branch may differ)
    final fallback = _subjectTeacherFallback[subject];
    if (fallback != null) return fallback;
    for (final a in _allAssignments) {
      final cl = _normKey(a['lesson'] ?? '');
      if (cl.isNotEmpty && s.isNotEmpty && (cl == s || cl.contains(s) || s.contains(cl))) {
        return a['teachers'] ?? 'Öğretmen Atanmamış';
      }
    }

    return 'Öğretmen Atanmamış';
  }

  // _buildStudentTaskButton and _buildStudentStatusDropdown are now inlined in _buildStudentRow

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildEmptyState(String message, {IconData icon = Icons.info_outline}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.indigo),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  String _getMonthName(int month) {
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return months[month - 1];
  }

  String _getMonthFullName(int month) {
    const months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    return months[month - 1];
  }
}

/// Öğrenci takibi: bir şube+ders grubu (önbelleğe alınır).
class _StudentGroup {
  final String branch;
  final String subject;
  final List<Map<String, dynamic>> students;
  final int criticalCount;
  final bool isCourse;
  const _StudentGroup({
    required this.branch,
    required this.subject,
    required this.students,
    required this.criticalCount,
    required this.isCourse,
  });
  String get key => "${branch}_$subject";
}

/// Öğrenci takibi: tembel (lazy) listedeki tek öğrenci satırı.
class _StudentEntry {
  final _StudentGroup group;
  final Map<String, dynamic> student;
  final bool isLast;
  const _StudentEntry(this.group, this.student, this.isLast);
}
