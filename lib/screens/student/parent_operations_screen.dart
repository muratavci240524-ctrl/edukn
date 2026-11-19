import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../services/daily_report_service.dart';
import '../../services/school_module_guard.dart';
import '../../services/user_permission_service.dart';
import '../portfolio/portfolio_screen.dart';
import '../school/daily_report/parent_daily_report_screen.dart';
import '../school/guidance/saved_study_programs_screen.dart';
import '../school/work_calendar_screen.dart';
import 'parent_accounting_screen.dart';
import 'parent_early_pickup_screen.dart';
import 'student_and_parent_tools_screen.dart';
import 'student_attendance_stats_screen.dart';
import 'student_etut_stats_screen.dart';
import 'student_exam_stats_screen.dart';
import 'student_homework_stats_screen.dart';
import 'student_lessons_screen.dart';
import 'student_personal_academic_tools_screen.dart';
import '../store/store_shop_screen.dart';
import '../canteen_user/canteen_parent_screen.dart';
import '../canteen_user/canteen_student_screen.dart';

class ParentOperationsScreen extends StatefulWidget {
  final String institutionId;
  final String? selectedStudentId;
  final Map<String, dynamic>? selectedStudentData;
  final bool isParentUser;

  const ParentOperationsScreen({
    Key? key,
    required this.institutionId,
    this.selectedStudentId,
    this.selectedStudentData,
    this.isParentUser = false,
  }) : super(key: key);

  @override
  State<ParentOperationsScreen> createState() => _ParentOperationsScreenState();
}

class _ParentOperationsScreenState extends State<ParentOperationsScreen> {
  String _selectedCategory = 'Tümü';
  Map<String, dynamic>? _studentData;
  bool _isLoadingStudent = true;
  bool _isParent = false;
  bool _dailyReportEnabled = false;
  Map<String, dynamic>? _appSettings;
  Map<String, dynamic>? _schoolData;

  bool get _isStoreModuleEnabled => SchoolModuleGuard.isSubModuleEnabled(
    _schoolData,
    'magaza_satis',
    'magaza_alisveris',
  );

  bool get _isKantinEnabled => SchoolModuleGuard.isSubModuleEnabled(
    _schoolData,
    'kantin',
    'kantin_veli',
  );

  // Veli & Öğrenci Özet İstatistikleri (Bugünkü yoklama, bekleyen ödev)
  String _todayAttendanceSummary = 'Kayıt Yok';
  int _activeHomeworkCount = 0;

  @override
  void initState() {
    super.initState();
    _isParent = widget.isParentUser;
    if (widget.selectedStudentData != null) {
      _studentData = Map<String, dynamic>.from(widget.selectedStudentData!);
      _isLoadingStudent = false;
      _loadDailyReportStatusForStudent(_studentData);
      _loadStudentLiveSummary();
    } else {
      _loadStudentInfo();
    }
    _resolveUserRole();
  }

  @override
  void didUpdateWidget(covariant ParentOperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isParentUser != widget.isParentUser) {
      _isParent = widget.isParentUser;
    }
    if (widget.selectedStudentId != oldWidget.selectedStudentId ||
        widget.selectedStudentData != oldWidget.selectedStudentData) {
      if (widget.selectedStudentData != null) {
        setState(() {
          _studentData = Map<String, dynamic>.from(widget.selectedStudentData!);
          _isLoadingStudent = false;
        });
        _loadDailyReportStatusForStudent(_studentData);
        _loadStudentLiveSummary();
      } else {
        _loadStudentInfo();
      }
    }
  }

  Future<void> _resolveUserRole() async {
    try {
      final cached = await UserPermissionService.loadUserData();
      if (cached != null) {
        final role = (cached['role'] ?? '').toString().toLowerCase();
        if (role == 'parent' || role == 'veli') {
          if (mounted) setState(() => _isParent = true);
          return;
        }
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final role = (doc.data()?['role'] ?? '').toString().toLowerCase();
        if (mounted && (role == 'parent' || role == 'veli')) {
          setState(() => _isParent = true);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDailyReportStatusForStudent(
    Map<String, dynamic>? st,
  ) async {
    try {
      final instId = widget.institutionId.toUpperCase();
      if (instId.isEmpty) return;
      final service = DailyReportService();
      final schoolDocId = await service.resolveSchoolDocId(instId);
      if (schoolDocId.isEmpty) return;
      final schoolSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolDocId)
          .get();
      final sData = schoolSnap.data();
      final appSettings = sData?['appSettings'] as Map<String, dynamic>?;
      final cfg = await service.loadConfig(schoolDocId);
      final stId = (st?['schoolTypeId'] ?? '').toString();
      final enabled = cfg.isEnabledForSchoolType(stId);
      if (mounted) {
        setState(() {
          _schoolData = sData;
          _appSettings = appSettings;
          _dailyReportEnabled = enabled;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadStudentLiveSummary() async {
    final st = _studentData;
    if (st == null) return;
    final stId = (st['id'] ?? widget.selectedStudentId ?? '').toString();
    final classId = (st['classId'] ?? '').toString();
    if (stId.isEmpty) return;

    try {
      final instIds = {
        widget.institutionId,
        widget.institutionId.toUpperCase(),
        widget.institutionId.toLowerCase(),
      }.where((s) => s.isNotEmpty).toList();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final res = await Future.wait([
        FirebaseFirestore.instance
            .collection('lessonAttendance')
            .where('institutionId', whereIn: instIds)
            .where('date', isEqualTo: todayStr)
            .get()
            .catchError(
              (_) => FirebaseFirestore.instance
                  .collection('lessonAttendance')
                  .limit(0)
                  .get(),
            ),
        classId.isNotEmpty
            ? FirebaseFirestore.instance
                  .collection('homeworks')
                  .where('institutionId', whereIn: instIds)
                  .where('classId', isEqualTo: classId)
                  .get()
                  .catchError(
                    (_) => FirebaseFirestore.instance
                        .collection('homeworks')
                        .limit(0)
                        .get(),
                  )
            : Future.value(null),
      ]);

      final attSnap = res[0] as QuerySnapshot<Map<String, dynamic>>;
      final hwSnap = res[1] as QuerySnapshot<Map<String, dynamic>>?;

      int presentCnt = 0;
      int absentCnt = 0;
      int lateCnt = 0;
      for (final d in attSnap.docs) {
        final statuses = Map<String, dynamic>.from(
          d.data()['studentStatuses'] ?? d.data()['attendance'] ?? {},
        );
        final myStatus = statuses[stId]?.toString().toLowerCase() ?? '';
        if (myStatus == 'present' || myStatus == 'var') {
          presentCnt++;
        } else if (myStatus == 'absent' || myStatus == 'yok') {
          absentCnt++;
        } else if (myStatus == 'late' || myStatus == 'gec') {
          lateCnt++;
        }
      }

      String attSummary = 'Bugün Yoklama Girilmedi';
      if (absentCnt > 0) {
        attSummary = '$absentCnt Ders Yok / $presentCnt Ders Var';
      } else if (lateCnt > 0) {
        attSummary = '$lateCnt Ders Geç / $presentCnt Ders Var';
      } else if (presentCnt > 0) {
        attSummary = 'Bugün $presentCnt Derste Mevcut';
      }

      int pendingHw = 0;
      if (hwSnap != null) {
        final now = DateTime.now();
        for (final doc in hwSnap.docs) {
          final due = (doc.data()['dueDate'] as Timestamp?)?.toDate();
          if (due == null ||
              due.isAfter(now.subtract(const Duration(days: 1)))) {
            pendingHw++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _todayAttendanceSummary = attSummary;
          _activeHomeworkCount = pendingHw;
        });
      }
    } catch (_) {}
  }

  bool _isAllowed(String keySuffix) {
    final prefix = _isParent ? 'p' : 's';
    final stId = (_studentData?['schoolTypeId'] ?? '').toString();
    return UserPermissionService.isAppSettingEnabled(
      _appSettings,
      '$prefix.$keySuffix',
      schoolTypeId: stId.isEmpty ? null : stId,
    );
  }

  Future<void> _loadStudentInfo() async {
    setState(() => _isLoadingStudent = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingStudent = false);
        return;
      }

      if (widget.selectedStudentId != null &&
          widget.selectedStudentId!.isNotEmpty) {
        final sDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(widget.selectedStudentId)
            .get();
        if (sDoc.exists && mounted) {
          final loaded = {'id': sDoc.id, ...sDoc.data()!};
          setState(() {
            _studentData = loaded;
            _isLoadingStudent = false;
          });
          _loadDailyReportStatusForStudent(loaded);
          _loadStudentLiveSummary();
          return;
        }
      }

      final instUpper = widget.institutionId.toUpperCase();
      final emailPrefix = (user.email ?? '').split('@').first;
      var q = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: instUpper)
          .where('username', isEqualTo: emailPrefix)
          .limit(1)
          .get();

      if (q.docs.isEmpty) {
        q = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: instUpper)
            .where('tcNo', isEqualTo: emailPrefix)
            .limit(1)
            .get();
      }

      if (q.docs.isNotEmpty && mounted) {
        final loaded = {'id': q.docs.first.id, ...q.docs.first.data()};
        setState(() {
          _studentData = loaded;
          _isLoadingStudent = false;
        });
        _loadDailyReportStatusForStudent(loaded);
        _loadStudentLiveSummary();
      } else if (mounted) {
        setState(() => _isLoadingStudent = false);
      }
    } catch (e) {
      debugPrint('Error loading student info in ParentOperationsScreen: $e');
      if (mounted) setState(() => _isLoadingStudent = false);
    }
  }

  String get _studentName =>
      _studentData?['fullName'] ??
      '${_studentData?['name'] ?? ''} ${_studentData?['surname'] ?? ''}'.trim();

  String get _studentNo =>
      (_studentData?['studentNo'] ??
              _studentData?['studentNumber'] ??
              _studentData?['no'] ??
              '')
          .toString()
          .trim();

  String get _className => (_studentData?['className'] ?? '').toString().trim();

  String _extractGradeLevel(Map<String, dynamic> st) {
    final direct = (st['classLevel'] ?? st['gradeLevel'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    final className = (st['className'] ?? '').toString();
    final digits = RegExp(r'\d+').firstMatch(className)?.group(0) ?? '';
    if (digits.isEmpty) return '';
    if (digits.startsWith('10') ||
        digits.startsWith('11') ||
        digits.startsWith('12')) {
      return digits.substring(0, 2);
    }
    return digits.substring(0, 1);
  }

  // ─── NAVİGASYON METOTLARI ─────────────────────────────────────────────────

  void _openToolsHub({String initialCategory = 'Tümü'}) {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentAndParentToolsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentData: _studentData!,
          isParentUser: _isParent,
          dailyReportEnabled: _dailyReportEnabled,
          storeEnabled: _isStoreModuleEnabled,
          kantinEnabled: _isKantinEnabled,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  void _openPersonalAcademicTool(int index) {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentPersonalAcademicToolsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentData: _studentData!,
          initialToolIndex: index,
          isParentView: _isParent,
        ),
      ),
    );
  }

  void _openMealList() {
    final parts = <String>[
      if (_isParent) 'Veli Paneli',
      if (_studentNo.isNotEmpty) _studentNo,
      if (_studentName.isNotEmpty) _studentName,
      if (_className.isNotEmpty) '($_className)',
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentMealMenuScreen(
          institutionId: widget.institutionId.toUpperCase(),
          schoolTypeId: (_studentData?['schoolTypeId'] ?? '').toString(),
          studentSubtitle: parts.join(' • '),
        ),
      ),
    );
  }

  void _openOnlineServices(int tab) {
    if (_studentData == null) return;
    final parts = <String>[
      if (_isParent) 'Veli Paneli',
      if (_studentNo.isNotEmpty) _studentNo,
      if (_studentName.isNotEmpty) _studentName,
      if (_className.isNotEmpty) '($_className)',
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentOnlineServicesScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentData: _studentData!,
          studentSubtitle: parts.join(' • '),
          initialTab: tab,
        ),
      ),
    );
  }

  void _navigateToEarlyPickup() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentEarlyPickupScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          initialStudentData: _studentData,
        ),
      ),
    );
  }

  void _navigateToDailyReport() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentDailyReportScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentName: _studentName,
          className: _className,
        ),
      ),
    );
  }

  void _navigateToLessons() {
    if (_studentData == null) return;
    final stId = (_studentData!['schoolTypeId'] ?? '').toString();
    final stName = (_studentData!['schoolTypeName'] ?? 'Okul').toString();
    final classId = (_studentData!['classId'] ?? '').toString();
    if (stId.isEmpty || classId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Öğrenci sınıf bilgisi bulunamadı.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentLessonsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          schoolTypeId: stId,
          schoolTypeName: stName,
          studentId: _studentData!['id'].toString(),
          classId: classId,
          className: _className,
        ),
      ),
    );
  }

  void _navigateToWorkCalendar() {
    if (_studentData == null) return;
    final stId = (_studentData!['schoolTypeId'] ?? '').toString();
    final stName = (_studentData!['schoolTypeName'] ?? 'Okul').toString();
    if (stId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkCalendarScreen(
          institutionId: widget.institutionId.toUpperCase(),
          schoolTypeId: stId,
          schoolTypeName: stName,
          isTeacher: true,
        ),
      ),
    );
  }

  void _navigateToAttendanceStats() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentAttendanceStatsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          classId: (_studentData!['classId'] ?? '').toString(),
          studentName: _studentName,
        ),
      ),
    );
  }

  void _navigateToHomeworkStats() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentHomeworkStatsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          classId: (_studentData!['classId'] ?? '').toString(),
          studentName: _studentName,
        ),
      ),
    );
  }

  void _navigateToEtutStats() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentEtutStatsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentName: _studentName,
          classId: (_studentData!['classId'] ?? '').toString(),
        ),
      ),
    );
  }

  void _navigateToExamStats() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentExamStatsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          classId: (_studentData!['classId'] ?? '').toString(),
          classLevel: _extractGradeLevel(_studentData!),
          studentName: _studentName,
          schoolNumber: _studentNo,
        ),
      ),
    );
  }

  void _openPortfolioTab(int tabIndex) {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PortfolioDetailView(
          student: _studentData!,
          institutionId: widget.institutionId.toUpperCase(),
          filteredStudents: [_studentData!],
          schoolSettings: const {},
          initialTab: tabIndex,
        ),
      ),
    );
  }

  void _navigateToPortfolio() => _openPortfolioTab(0);

  void _navigateToGuidanceInterview() => _openPortfolioTab(8);

  void _navigateToGuidanceActivity() => _openPortfolioTab(13);

  void _navigateToSavedStudyPrograms() {
    if (_studentData == null) return;
    final stId = (_studentData!['schoolTypeId'] ?? '').toString();
    if (stId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedStudyProgramsScreen(
          institutionId: widget.institutionId.toUpperCase(),
          schoolTypeId: stId,
          isTeacher: false,
          allowedStudentIds: [_studentData!['id'].toString()],
        ),
      ),
    );
  }

  void _navigateToDevelopmentReports() => _openPortfolioTab(10);

  void _navigateToAccounting() {
    if (_studentData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentAccountingScreen(
          institutionId: widget.institutionId.toUpperCase(),
          studentId: _studentData!['id'].toString(),
          studentName: _studentName,
          studentNo: _studentNo,
        ),
      ),
    );
  }

  void _navigateToStore() {
    final stId = (_studentData?['schoolTypeId'] ?? '').toString().trim();
    final stName = (_studentData?['schoolTypeName'] ?? '').toString().trim();
    final studentId = (_studentData?['id'] ?? widget.selectedStudentId ?? '')
        .toString()
        .trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreShopScreen(
          institutionId: widget.institutionId.toUpperCase(),
          schoolTypeId: stId.isEmpty ? null : stId,
          schoolTypeName: stName.isEmpty ? null : stName,
          buyerRole: _isParent ? 'veli' : 'ogrenci',
          studentId: studentId.isEmpty ? null : studentId,
          studentName: _studentName.isEmpty ? null : _studentName,
        ),
      ),
    );
  }

  void _navigateToKantin() {
    final studentId = (_studentData?['id'] ?? widget.selectedStudentId ?? '')
        .toString()
        .trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isParent
            ? CanteenParentScreen(
                institutionId: widget.institutionId.toUpperCase(),
                studentId: studentId.isEmpty ? null : studentId,
                studentName: _studentName.isEmpty ? null : _studentName,
              )
            : CanteenStudentScreen(
                institutionId: widget.institutionId.toUpperCase(),
                studentId: studentId,
                studentName: _studentName.isEmpty ? null : _studentName,
              ),
      ),
    );
  }

  // ─── ARAYÜZ BİLEŞENLERİ ───────────────────────────────────────────────────

  Widget _buildOverviewBanner(bool isMobile) {
    if (_studentData == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        16,
        isMobile ? 16 : 24,
        4,
      ),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isParent
              ? [const Color(0xFF0F766E), const Color(0xFF0D9488)]
              : [const Color(0xFF312E81), const Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color:
                (_isParent ? const Color(0xFF0D9488) : const Color(0xFF4F46E5))
                    .withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _isParent
                          ? 'VELİ BİLGİ VE İŞLEM MERKEZİ'
                          : 'ÖĞRENCİ PANELİ',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_studentNo.isNotEmpty ? "$_studentNo • " : ""}$_studentName${_className.isNotEmpty ? " ($_className)" : ""}',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 16.5 : 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    '📍 $_todayAttendanceSummary',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  Text(
                    '📚 Aktif Ödev: $_activeHomeworkCount',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.92),
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
              if (_isParent)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                  ),
                  onPressed: _navigateToEarlyPickup,
                  icon: const Icon(
                    Icons.directions_car_filled_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Erken Alma Talebi',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                ),
                onPressed: _openMealList,
                icon: const Icon(Icons.restaurant_menu_rounded, size: 17),
                label: const Text(
                  'Yemek Listesi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_isStoreModuleEnabled)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _navigateToStore,
                  icon: const Icon(Icons.storefront_rounded, size: 17),
                  label: const Text(
                    'Mağaza',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if (_isKantinEnabled)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _navigateToKantin,
                  icon: const Icon(Icons.fastfood_rounded, size: 17),
                  label: const Text(
                    'Kantin',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _openToolsHub(),
                icon: const Icon(Icons.handyman_rounded, size: 17),
                label: const Text(
                  'Araçlar Merkezi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    final categories = [
      {'label': 'Tümü', 'icon': Icons.grid_view_rounded},
      {'label': 'Araçlar', 'icon': Icons.handyman_rounded},
      {'label': 'Mağaza', 'icon': Icons.storefront_rounded},
      if (_isKantinEnabled) {'label': 'Kantin', 'icon': Icons.fastfood_rounded},
      if (_isAllowed('egitim_islemleri'))
        {'label': 'Eğitim', 'icon': Icons.school_rounded},
      if (_isAllowed('rehberlik_islemleri'))
        {'label': 'Rehberlik', 'icon': Icons.folder_special_rounded},
      if (_isParent && _isAllowed('muhasebe_islemleri'))
        {'label': 'Muhasebe', 'icon': Icons.account_balance_wallet_rounded},
    ];

    return SizedBox(
      width: double.infinity,
      height: 112,
      child: Center(
        child: ScrollConfiguration(
          behavior: _MouseDraggableScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat['label'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _selectedCategory = cat['label'] as String,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? Colors.indigo.withValues(alpha: 0.28)
                                : Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: isSelected
                              ? Colors.indigo
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            color: isSelected
                                ? Colors.white
                                : Colors.indigo.shade400,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cat['label'] as String,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridSections(bool isMobile) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth > 1440 ? 1440.0 : screenWidth;
    final availableWidth = contentWidth - (isMobile ? 32 : 48);

    final isFiltered = _selectedCategory != 'Tümü';
    double cardWidth;
    if (isFiltered) {
      cardWidth = availableWidth;
    } else if (availableWidth > 1020) {
      cardWidth = (availableWidth - 48) / 3;
    } else if (availableWidth > 680) {
      cardWidth = (availableWidth - 24) / 2;
    } else {
      cardWidth = availableWidth;
    }

    // 1. ARAÇLAR (Öğrenci & Veli Özel Araçlar + Online İşlemler + Yemek Listesi + Kişisel Akademik)
    final List<Map<String, dynamic>> araclarItems = [
      if (_isParent)
        {
          'title': 'Erken Alma & Okula Geldim Talebi',
          'onTap': _navigateToEarlyPickup,
        },
      {
        'title': 'Yemek Listesi (Günlük & Haftalık Menü)',
        'onTap': _openMealList,
      },
      {
        'title': 'Online İşlemler & Eğitim Portalları (SSO)',
        'onTap': () => _openOnlineServices(0),
      },
      {
        'title': 'Online Sınav & Deneme Merkezi',
        'onTap': () => _openOnlineServices(1),
      },
      {
        'title': 'Kişisel LGS / YKS Puan & Hedef Simülatörü',
        'onTap': () => _openPersonalAcademicTool(0),
      },
      {
        'title': 'Kişisel Deneme Gelişim & Net Koçum',
        'onTap': () => _openPersonalAcademicTool(1),
      },
      {
        'title': 'Branş & Kazanım Eksik Karnem',
        'onTap': () => _openPersonalAcademicTool(2),
      },
      {
        'title': 'Yazılı Ortalaması & Takdir / Teşekkür Hesaplayıcı',
        'onTap': () => _openPersonalAcademicTool(3),
      },
    ];

    // 2. EĞİTİM İŞLEMLERİ
    final List<Map<String, dynamic>> egitimItems = [
      if (_isParent && _isAllowed('egitim_islemleri.erken_alma'))
        {
          'title': 'Erken Alma & Okula Geldim Bildirimi',
          'onTap': _navigateToEarlyPickup,
        },
      if (_dailyReportEnabled && _isAllowed('egitim_islemleri.gunluk_rapor'))
        {'title': 'Günlük Karne', 'onTap': _navigateToDailyReport},
      if (_isAllowed('egitim_islemleri.ders_programi'))
        {'title': 'Ders Programı', 'onTap': _navigateToLessons},
      if (_isAllowed('egitim_islemleri.calisma_takvimi'))
        {'title': 'Çalışma Takvimi', 'onTap': _navigateToWorkCalendar},
      if (_isAllowed('egitim_islemleri.devamsizlik_durumu'))
        {'title': 'Devamsızlık Durumu', 'onTap': _navigateToAttendanceStats},
      if (_isAllowed('egitim_islemleri.odevler'))
        {'title': 'Ödevler', 'onTap': _navigateToHomeworkStats},
      if (_isAllowed('egitim_islemleri.etut_islemleri'))
        {'title': 'Etüt İşlemleri', 'onTap': _navigateToEtutStats},
      if (_isAllowed('egitim_islemleri.sinavlar_ve_sonuclar'))
        {'title': 'Sınavlar ve Sonuçlar', 'onTap': _navigateToExamStats},
    ];

    // 3. REHBERLİK İŞLEMLERİ
    final List<Map<String, dynamic>> rehberlikItems = [
      if (_isAllowed('rehberlik_islemleri.ogrenci_portfolyosu'))
        {'title': 'Öğrenci Portfolyosu', 'onTap': _navigateToPortfolio},
      if (_isAllowed('rehberlik_islemleri.gorusmeler'))
        {'title': 'Görüşmeler', 'onTap': _navigateToGuidanceInterview},
      if (_isAllowed('rehberlik_islemleri.etkinlikler'))
        {'title': 'Etkinlikler', 'onTap': _navigateToGuidanceActivity},
      if (_isAllowed('rehberlik_islemleri.calisma_programlarim'))
        {
          'title': 'Çalışma Programlarım',
          'onTap': _navigateToSavedStudyPrograms,
        },
      if (_isAllowed('rehberlik_islemleri.gelisim_raporlari'))
        {
          'title': '360 Gelişim Raporları',
          'onTap': _navigateToDevelopmentReports,
        },
    ];

    // 4. MUHASEBE (Sadece Veli)
    final List<Map<String, dynamic>> muhasebeItems = [
      if (_isAllowed('muhasebe_islemleri.odeme_plani'))
        {'title': 'Ödeme Planı ve Taksitler', 'onTap': _navigateToAccounting},
    ];

    final List<Map<String, dynamic>> magazaItems = [
      {
        'title': 'Okul & Genel Merkez Mağazası (Online Alışveriş)',
        'onTap': _navigateToStore,
      },
      {
        'title': 'Siparişlerim & Kargo / Teslimat Takibi',
        'onTap': _navigateToStore,
      },
    ];

    final List<Map<String, dynamic>> kantinItems = [
      {'title': 'Kantin Bakiyesi & Hareketler', 'onTap': _navigateToKantin},
      {'title': 'Kantin Ürünleri', 'onTap': _navigateToKantin},
    ];

    final List<_ParentModuleCardWidget> allModules = [
      _ParentModuleCardWidget(
        title: 'ARAÇLAR MERKEZİ',
        badge: 'Araçlar',
        icon: Icons.handyman_rounded,
        color: const Color(0xFF0D9488),
        cardWidth: cardWidth,
        isMobile: isMobile,
        category: 'Araçlar',
        showAllItems: isFiltered,
        items: araclarItems,
        buttonLabel: 'TÜM ARAÇLARI AÇ',
        onTap: () => _openToolsHub(),
      ),
      if (_isStoreModuleEnabled)
        _ParentModuleCardWidget(
          title: 'MAĞAZA & ONLİNE ALIŞVERİŞ',
          badge: 'Mağaza',
          icon: Icons.storefront_rounded,
          color: Colors.deepOrange,
          cardWidth: cardWidth,
          isMobile: isMobile,
          category: 'Mağaza',
          showAllItems: isFiltered,
          items: magazaItems,
          buttonLabel: 'MAĞAZAYI AÇ',
          onTap: _navigateToStore,
        ),
      if (_isKantinEnabled)
        _ParentModuleCardWidget(
          title: 'KANTİN',
          badge: 'Kantin',
          icon: Icons.fastfood_rounded,
          color: const Color(0xFFE53935),
          cardWidth: cardWidth,
          isMobile: isMobile,
          category: 'Kantin',
          showAllItems: isFiltered,
          items: kantinItems,
          buttonLabel: 'KANTİNİ AÇ',
          onTap: _navigateToKantin,
        ),
      if (_isAllowed('egitim_islemleri') && egitimItems.isNotEmpty)
        _ParentModuleCardWidget(
          title: 'EĞİTİM İŞLEMLERİ',
          badge: 'Eğitim',
          icon: Icons.school_rounded,
          color: Colors.orange,
          cardWidth: cardWidth,
          isMobile: isMobile,
          category: 'Eğitim',
          showAllItems: isFiltered,
          items: egitimItems,
          onTap: () => setState(() => _selectedCategory = 'Eğitim'),
        ),
      if (_isAllowed('rehberlik_islemleri') && rehberlikItems.isNotEmpty)
        _ParentModuleCardWidget(
          title: 'REHBERLİK İŞLEMLERİ',
          badge: 'Rehberlik',
          icon: Icons.folder_special_rounded,
          color: Colors.deepPurple,
          cardWidth: cardWidth,
          isMobile: isMobile,
          category: 'Rehberlik',
          showAllItems: isFiltered,
          items: rehberlikItems,
          onTap: () => setState(() => _selectedCategory = 'Rehberlik'),
        ),
      if (_isParent &&
          _isAllowed('muhasebe_islemleri') &&
          muhasebeItems.isNotEmpty)
        _ParentModuleCardWidget(
          title: 'MUHASEBE İŞLEMLERİ',
          badge: 'Finans',
          icon: Icons.account_balance_wallet_rounded,
          color: Colors.blue,
          cardWidth: cardWidth,
          isMobile: isMobile,
          category: 'Muhasebe',
          showAllItems: isFiltered,
          items: muhasebeItems,
          onTap: () => setState(() => _selectedCategory = 'Muhasebe'),
        ),
    ];

    final filteredModules =
        (_selectedCategory == 'Tümü'
                ? allModules
                : allModules
                      .where((m) => m.category == _selectedCategory)
                      .toList())
            .where((m) => m.items.isNotEmpty)
            .toList();

    return Wrap(
      key: ValueKey('parent_grid_${_selectedCategory}_$isMobile'),
      spacing: 24,
      runSpacing: 24,
      children: filteredModules,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: _isLoadingStudent
          ? const Center(child: CircularProgressIndicator())
          : _studentData == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_off_outlined,
                    size: 56,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Öğrenci kaydı bulunamadı.',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildOverviewBanner(isMobile),
                  _buildCategorySelector(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : 24,
                          vertical: 8,
                        ),
                        child: _buildGridSections(isMobile),
                      ),
                    ),
                  ),
                  const SizedBox(height: 110),
                ],
              ),
            ),
    );
  }
}

class _MouseDraggableScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class _ParentModuleCardWidget extends StatefulWidget {
  final String title;
  final String badge;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final VoidCallback onTap;
  final double cardWidth;
  final bool isMobile;
  final String category;
  final bool showAllItems;
  final String? buttonLabel;

  const _ParentModuleCardWidget({
    Key? key,
    required this.title,
    required this.badge,
    required this.icon,
    required this.color,
    required this.items,
    required this.onTap,
    required this.cardWidth,
    required this.isMobile,
    required this.category,
    this.showAllItems = false,
    this.buttonLabel,
  }) : super(key: key);

  @override
  State<_ParentModuleCardWidget> createState() =>
      _ParentModuleCardWidgetState();
}

class _ParentModuleCardWidgetState extends State<_ParentModuleCardWidget> {
  bool isCardHovered = false;
  int? hoveredItemIndex;

  @override
  Widget build(BuildContext context) {
    final displayedItems = widget.showAllItems
        ? widget.items
        : widget.items.take(4).toList();
    final remainingCount = widget.items.length - displayedItems.length;
    final String label = remainingCount > 0
        ? (widget.buttonLabel ?? '+$remainingCount işlem daha görüntüle')
        : (widget.buttonLabel ?? 'GÖRÜNTÜLE');

    return MouseRegion(
      onEnter: (_) => setState(() => isCardHovered = true),
      onExit: (_) => setState(() => isCardHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        width: widget.cardWidth,
        height: (widget.isMobile || widget.showAllItems) ? null : 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isCardHovered || widget.showAllItems ? 0.08 : 0.03,
              ),
              blurRadius: isCardHovered || widget.showAllItems ? 30 : 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: isCardHovered || widget.showAllItems
                ? widget.color.withValues(alpha: 0.3)
                : Colors.indigo.withValues(alpha: 0.05),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(widget.isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 28),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.badge,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: widget.isMobile ? 18 : 20,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 18),
            ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                final isHovered = hoveredItemIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => hoveredItemIndex = index),
                    onExit: (_) => setState(() => hoveredItemIndex = null),
                    child: InkWell(
                      onTap: item['onTap'] as VoidCallback,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isHovered
                                    ? widget.color
                                    : Colors.blueGrey.shade200,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isHovered
                                      ? widget.color
                                      : Colors.blueGrey.shade700,
                                  fontSize: 13.5,
                                  fontWeight: isHovered
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isHovered
                                  ? widget.color
                                  : Colors.blueGrey.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (!widget.isMobile && !widget.showAllItems) const Spacer(),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCardHovered
                      ? widget.color
                      : const Color(0xFFF1F5F9),
                  foregroundColor: isCardHovered
                      ? Colors.white
                      : Colors.blueGrey.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
