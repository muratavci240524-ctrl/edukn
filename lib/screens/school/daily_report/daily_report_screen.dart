import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/school/daily_report_models.dart';
import '../../../services/daily_report_service.dart';
import '../../../widgets/edukn_app_bar.dart';
import 'daily_report_sheets.dart';
import 'parent_daily_report_screen.dart';

/// Öğretmen ve Yönetici Günlük Rapor (Günlük Karne) Yönetim Ekranı
/// - Öğretmen: Yalnızca kendisine atanmış sınıfları ve kendi öğrencilerini görür.
/// - Yönetici: Tüm okul türlerini, sınıfları ve tüm öğrencileri görür; modül ayarlarını yönetebilir.
class DailyReportScreen extends StatefulWidget {
  final String institutionId;
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;

  const DailyReportScreen({
    super.key,
    required this.institutionId,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
  });

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  final DailyReportService _service = DailyReportService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String _institutionId = '';
  String _schoolDocId = '';
  String _actorUid = '';
  String _actorName = 'Öğretmen';
  bool _isAdmin = false;

  DailyReportConfigModel _config = const DailyReportConfigModel();
  List<({String id, String name})> _schoolTypes = [];
  String _selectedSchoolTypeId = '';

  List<DailyReportClassInfo> _allClasses = [];
  List<DailyReportStudentInfo> _allStudents = [];
  String _selectedClassId = ''; // Admin için '' = Tüm Sınıflar olabilir; öğretmen için ilk sınıf seçilir

  DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | 'filled' | 'empty' | 'low_meal' | 'seen'

  String get _dateKey => DailyReportService.formatDateKey(_selectedDate);

  @override
  void initState() {
    super.initState();
    _selectedSchoolTypeId = (widget.fixedSchoolTypeId ?? '').trim();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.institutionId,
      );
      final instId = actor.institutionId.isNotEmpty
          ? actor.institutionId
          : widget.institutionId.trim();
      final schoolDocId = await _service.resolveSchoolDocId(instId);
      final config = await _service.loadConfig(schoolDocId);

      List<({String id, String name})> schoolTypes = [];
      if ((widget.fixedSchoolTypeId ?? '').trim().isEmpty && actor.isAdmin) {
        schoolTypes = await _service.loadSchoolTypes(instId);
      }

      final accessible = await _service.loadAccessibleClassesAndStudents(
        institutionId: instId,
        isAdmin: actor.isAdmin,
        validTeacherIds: actor.validTeacherIds,
        fixedSchoolTypeId: widget.fixedSchoolTypeId,
      );

      String initialClassId = _selectedClassId;
      if (accessible.classes.isNotEmpty) {
        final stillExists =
            accessible.classes.any((c) => c.id == initialClassId);
        if (!stillExists) {
          initialClassId = accessible.classes.first.id;
        }
      } else {
        initialClassId = '';
      }

      if (mounted) {
        setState(() {
          _institutionId = instId;
          _schoolDocId = schoolDocId;
          _actorUid = actor.uid;
          _actorName = actor.name;
          _isAdmin = actor.isAdmin;
          _config = config;
          _schoolTypes = schoolTypes;
          _allClasses = accessible.classes;
          _allStudents = accessible.students;
          _selectedClassId = initialClassId;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('DailyReportScreen bootstrap error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DailyReportClassInfo> get _visibleClasses {
    if (_selectedSchoolTypeId.isEmpty) return _allClasses;
    return _allClasses
        .where(
          (c) =>
              c.schoolTypeId.isEmpty || c.schoolTypeId == _selectedSchoolTypeId,
        )
        .toList();
  }

  List<DailyReportStudentInfo> get _classScopedStudents {
    Iterable<DailyReportStudentInfo> list = _allStudents;
    if (_selectedSchoolTypeId.isNotEmpty) {
      list = list.where(
        (s) =>
            s.schoolTypeId.isEmpty || s.schoolTypeId == _selectedSchoolTypeId,
      );
    }
    if (_selectedClassId.isNotEmpty) {
      list = list.where((s) => s.classId == _selectedClassId);
    }
    return list.toList();
  }

  DailyReportClassInfo? get _activeClassInfo {
    for (final c in _visibleClasses) {
      if (c.id == _selectedClassId) return c;
    }
    return null;
  }

  void _shiftDate(int days) {
    final next = _selectedDate.add(Duration(days: days));
    final today = DateTime.now();
    final cleanToday = DateTime(today.year, today.month, today.day);
    final cleanNext = DateTime(next.year, next.month, next.day);
    if (cleanNext.isAfter(cleanToday)) return;
    setState(() => _selectedDate = cleanNext);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  String _prettyDateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    const weekdays = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    final datePart =
        '${target.day} ${months[target.month - 1]} ${weekdays[target.weekday - 1]}';
    if (target == today) return 'Bugün • $datePart';
    if (target == today.subtract(const Duration(days: 1))) {
      return 'Dün • $datePart';
    }
    return '$datePart ${target.year}';
  }

  String get _activeScopeSchoolTypeId {
    final fixed = (widget.fixedSchoolTypeId ?? '').trim();
    if (fixed.isNotEmpty) return fixed;
    if (_selectedSchoolTypeId.isNotEmpty) return _selectedSchoolTypeId;
    final clsSt = (_activeClassInfo?.schoolTypeId ?? '').trim();
    return clsSt;
  }

  DailyReportConfigModel get _effectiveConfig =>
      _config.forSchoolType(_activeScopeSchoolTypeId);

  Future<void> _openBulkSheet(
    List<DailyReportStudentInfo> targetStudents,
    Map<String, DailyReportModel> reportsMap,
  ) async {
    if (targetStudents.isEmpty) return;
    final classLabel = _activeClassInfo?.name ??
        (widget.fixedSchoolTypeName ?? 'Seçili Öğrenciler');
    final count = await BulkClassDailyReportSheet.show(
      context,
      institutionId: _institutionId,
      schoolDocId: _schoolDocId,
      dateKey: _dateKey,
      className: classLabel,
      classStudents: targetStudents,
      existingReports: reportsMap,
      config: _effectiveConfig,
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (count != null && count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ $count öğrencinin günlük karnesi güncellendi ve velilere anlık yayınlandı.',
          ),
          backgroundColor: const Color(0xFF0D9488),
        ),
      );
    }
  }

  Future<void> _openQuickActivitySheet(
    List<DailyReportStudentInfo> targetStudents,
    Map<String, DailyReportModel> reportsMap,
  ) async {
    if (targetStudents.isEmpty) return;
    final classLabel = _activeClassInfo?.name ??
        (widget.fixedSchoolTypeName ?? 'Seçili Sınıf');
    final ok = await QuickClassActivitySheet.show(
      context,
      institutionId: _institutionId,
      schoolDocId: _schoolDocId,
      dateKey: _dateKey,
      className: classLabel,
      classStudents: targetStudents,
      existingReports: reportsMap,
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Etkinlik / ders akışı sınıfa eklendi.'),
          backgroundColor: Color(0xFF4F46E5),
        ),
      );
    }
  }

  Future<void> _openStudentEditor(
    DailyReportStudentInfo student,
    DailyReportModel? existing,
  ) async {
    final studentConfig = _config.forSchoolType(
      student.schoolTypeId.isNotEmpty
          ? student.schoolTypeId
          : _activeScopeSchoolTypeId,
    );
    final saved = await StudentDailyReportEditorSheet.show(
      context,
      institutionId: _institutionId,
      schoolDocId: _schoolDocId,
      dateKey: _dateKey,
      student: student,
      existing: existing,
      config: studentConfig,
      actorUid: _actorUid,
      actorName: _actorName,
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ ${student.fullName} günlük karnesi kaydedildi.'),
          backgroundColor: const Color(0xFF4F46E5),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openParentPreview(DailyReportStudentInfo student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentDailyReportScreen(
          institutionId: _institutionId,
          studentId: student.id,
          studentName: student.fullName,
          className: student.className,
          initialDate: _selectedDate,
          isPreviewMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Günlük Rapor (Günlük Karne)',
        institutionId: _institutionId.isNotEmpty
            ? _institutionId
            : widget.institutionId,
        subtitle: widget.fixedSchoolTypeName,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Yenile',
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_config.isEnabledForSchoolType(_activeScopeSchoolTypeId) &&
                  !_isAdmin
              ? _buildDisabledNotice()
              : StreamBuilder<Map<String, DailyReportModel>>(
                  stream: _service.watchReportsForDate(
                    schoolDocId: _schoolDocId,
                    dateKey: _dateKey,
                  ),
                  builder: (context, snap) {
                    final reportsMap = snap.data ?? const {};
                    return _buildMainBody(isMobile, reportsMap);
                  },
                ),
    );
  }

  Widget _buildDisabledNotice() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline_rounded,
              size: 56,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 14),
            Text(
              'Günlük Rapor Modülü Bu Kademede Kapalı',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Okul yönetimi Sistem Ayarları -> Uygulama Ayarları üzerinden Günlük Rapor modülünü aktif hale getirebilir.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainBody(
    bool isMobile,
    Map<String, DailyReportModel> reportsMap,
  ) {
    final scopedStudents = _classScopedStudents;

    // İstatistikler
    int filledCount = 0;
    int seenCount = 0;
    int lowMealCount = 0;

    for (final st in scopedStudents) {
      final r = reportsMap[st.id];
      if (r != null && r.hasAnyContent) {
        filledCount++;
        if (r.parentSeenAt != null) seenCount++;
        if (r.breakfast.status == 'little' ||
            r.breakfast.status == 'none' ||
            r.lunch.status == 'little' ||
            r.lunch.status == 'none') {
          lowMealCount++;
        }
      }
    }

    // Arama + Durum Filtresi
    final q = _searchQuery.trim().toLowerCase();
    final filteredStudents = scopedStudents.where((st) {
      if (q.isNotEmpty &&
          !st.fullName.toLowerCase().contains(q) &&
          !st.className.toLowerCase().contains(q) &&
          !st.studentNo.toLowerCase().contains(q)) {
        return false;
      }
      final r = reportsMap[st.id];
      final hasData = r != null && r.hasAnyContent;
      switch (_statusFilter) {
        case 'filled':
          return hasData;
        case 'empty':
          return !hasData;
        case 'low_meal':
          return hasData &&
              (r.breakfast.status == 'little' ||
                  r.breakfast.status == 'none' ||
                  r.lunch.status == 'little' ||
                  r.lunch.status == 'none');
        case 'seen':
          return hasData && r.parentSeenAt != null;
        default:
          return true;
      }
    }).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            if (!_config.isEnabledForSchoolType(_activeScopeSchoolTypeId) &&
                _isAdmin)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Modül bu kademe için öğretmen ve velilere kapalı durumda. Açmak veya karne bölümlerini düzenlemek için Genel / Okul Türü içerisindeki Sistem Ayarları -> Uygulama Ayarları ekranını kullanabilirsiniz.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Üst Tarih + Sınıf Seçici + Hızlı İşlem Barı
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 14 : 22,
                  16,
                  isMobile ? 14 : 22,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDateAndScopeHeader(isMobile),
                    const SizedBox(height: 12),
                    _buildClassChips(reportsMap),
                    const SizedBox(height: 14),
                    _buildSummaryAndBulkActions(
                      isMobile: isMobile,
                      totalCount: scopedStudents.length,
                      filledCount: filledCount,
                      seenCount: seenCount,
                      lowMealCount: lowMealCount,
                      scopedStudents: scopedStudents,
                      reportsMap: reportsMap,
                    ),
                    const SizedBox(height: 14),
                    _buildSearchAndFilterBar(
                      totalCount: scopedStudents.length,
                      filledCount: filledCount,
                      lowMealCount: lowMealCount,
                      seenCount: seenCount,
                    ),
                  ],
                ),
              ),
            ),

            if (_allStudents.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.child_care_rounded,
                            size: 34,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _isAdmin
                              ? 'Bu kademede aktif sınıf veya öğrenci bulunamadı.'
                              : 'Size atanmış sınıf veya öğrenci bulunamadı.',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isAdmin
                              ? 'Şube Tanımları ve Öğrenci Kayıt ekranından sınıf/öğrenci ekleyebilirsiniz.'
                              : 'Sınıf öğretmenliği veya ders atamanız tanımlandığında öğrencileriniz burada listelenir.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (filteredStudents.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Seçili filtreye uygun öğrenci bulunamadı.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 14 : 22,
                  6,
                  isMobile ? 14 : 22,
                  36,
                ),
                sliver: SliverList.separated(
                  itemCount: filteredStudents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final st = filteredStudents[i];
                    final rep = reportsMap[st.id];
                    return _buildStudentReportCard(
                      student: st,
                      report: rep,
                      isMobile: isMobile,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateAndScopeHeader(bool isMobile) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        // Tarih Gezgini
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Önceki Gün',
                onPressed: () => _shiftDate(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                visualDensity: VisualDensity.compact,
              ),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Color(0xFF4F46E5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _prettyDateLabel(_selectedDate),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sonraki Gün',
                onPressed: isToday ? null : () => _shiftDate(1),
                icon: const Icon(Icons.chevron_right_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Yönetici için Okul Türü Filtresi (Genel panelden girildiyse)
        if (_isAdmin && _schoolTypes.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSchoolTypeId,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Tüm Okul Türleri'),
                  ),
                  ..._schoolTypes.map(
                    (st) => DropdownMenuItem(
                      value: st.id,
                      child: Text(st.name),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedSchoolTypeId = val ?? '';
                    final visible = _visibleClasses;
                    if (_selectedClassId.isNotEmpty &&
                        !visible.any((c) => c.id == _selectedClassId)) {
                      _selectedClassId =
                          visible.isNotEmpty ? visible.first.id : '';
                    }
                  });
                },
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isAdmin
                  ? const Color(0xFFEEF2FF)
                  : const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAdmin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_pin_rounded,
                  size: 16,
                  color: _isAdmin
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF0D9488),
                ),
                const SizedBox(width: 6),
                Text(
                  _isAdmin
                      ? 'Yönetici Görünümü (Tüm Öğrenciler)'
                      : 'Öğretmen Görünümü (Sınıflarım)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _isAdmin
                        ? const Color(0xFF3730A3)
                        : const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildClassChips(Map<String, DailyReportModel> reportsMap) {
    final classes = _visibleClasses;
    if (classes.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          if (_isAdmin && classes.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildClassChipItem(
                label: 'Tüm Sınıflar',
                subCount: '${_allStudents.length}',
                isSelected: _selectedClassId.isEmpty,
                onTap: () => setState(() => _selectedClassId = ''),
              ),
            ),
          ...classes.map((cls) {
            final clsStudents =
                _allStudents.where((s) => s.classId == cls.id).toList();
            final done = clsStudents
                .where((s) => reportsMap[s.id]?.hasAnyContent == true)
                .length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildClassChipItem(
                label: cls.name,
                subCount: '$done/${clsStudents.length}',
                isSelected: _selectedClassId == cls.id,
                onTap: () => setState(() => _selectedClassId = cls.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildClassChipItem({
    required String label,
    required String subCount,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4F46E5)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room_rounded,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                subCount,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryAndBulkActions({
    required bool isMobile,
    required int totalCount,
    required int filledCount,
    required int seenCount,
    required int lowMealCount,
    required List<DailyReportStudentInfo> scopedStudents,
    required Map<String, DailyReportModel> reportsMap,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF312E81).withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _activeClassInfo != null
                        ? '${_activeClassInfo!.name} Günlük Karne Akışı'
                        : 'Kurum Geneli Günlük Karne Özeti',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'İster tüm sınıfa tek dokunuşla girip istisna öğrencileri düzenleyin, ister öğrenci öğrenci işleyin.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFE0E7FF),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: scopedStudents.isEmpty
                        ? null
                        : () => _openBulkSheet(scopedStudents, reportsMap),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text(
                      'Tüm Sınıfa Toplu İşle',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_effectiveConfig.trackActivities)
                    ElevatedButton.icon(
                      onPressed: scopedStudents.isEmpty
                          ? null
                          : () => _openQuickActivitySheet(
                                scopedStudents,
                                reportsMap,
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF312E81),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text(
                        'Etkinlik / Ders Ekle',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatBadge(
                icon: Icons.groups_rounded,
                label: 'Öğrenci',
                value: '$totalCount',
              ),
              _buildStatBadge(
                icon: Icons.assignment_turned_in_rounded,
                label: 'Karne Girilen',
                value: '$filledCount / $totalCount',
              ),
              _buildStatBadge(
                icon: Icons.visibility_rounded,
                label: 'Veli Gördü',
                value: '$seenCount',
              ),
              _buildStatBadge(
                icon: Icons.restaurant_rounded,
                label: 'Az Yedi / Yemedi',
                value: '$lowMealCount',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Color(0xFFE0E7FF)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar({
    required int totalCount,
    required int filledCount,
    required int lowMealCount,
    required int seenCount,
  }) {
    final filters = [
      (key: 'all', label: 'Tümü ($totalCount)'),
      (key: 'empty', label: 'Girilmeyen (${totalCount - filledCount})'),
      (key: 'filled', label: 'Girilen ($filledCount)'),
      (key: 'low_meal', label: 'Az Yiyen / Yemedi ($lowMealCount)'),
      (key: 'seen', label: 'Veli Okudu ($seenCount)'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: 'Öğrenci adı, numarası veya sınıf ara...',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
              size: 20,
            ),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF4F46E5), width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((f) {
              final sel = _statusFilter == f.key;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: sel,
                  onSelected: (_) => setState(() => _statusFilter = f.key),
                  selectedColor: const Color(0xFFE0E7FF),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    color: sel
                        ? const Color(0xFF312E81)
                        : const Color(0xFF475569),
                  ),
                  side: BorderSide(
                    color: sel
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentReportCard({
    required DailyReportStudentInfo student,
    required DailyReportModel? report,
    required bool isMobile,
  }) {
    final hasReport = report != null && report.hasAnyContent;
    final moodMeta =
        report != null ? DailyReportCatalog.moodMeta(report.mood) : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasReport
              ? const Color(0xFFC7D2FE)
              : const Color(0xFFE2E8F0),
          width: hasReport ? 1.3 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _openStudentEditor(student, report),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Satır: Öğrenci Kimliği + Veli Okundu + Karne Düzenle / Önizleme
              Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: hasReport
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFF1F5F9),
                    child: Text(
                      moodMeta?.emoji ??
                          (student.fullName.isNotEmpty
                              ? student.fullName[0].toUpperCase()
                              : 'Ö'),
                      style: TextStyle(
                        fontSize: moodMeta != null ? 20 : 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                student.fullName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (student.allergyOrHealthInfo.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message:
                                    'Alerji/Sağlık: ${student.allergyOrHealthInfo}',
                                child: const Icon(
                                  Icons.medical_information_rounded,
                                  size: 16,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              student.className,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            if (report?.parentSeenAt != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '👁️ Veli Gördü ${DateFormat('HH:mm').format(report!.parentSeenAt!)} ${report.parentReaction}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF166534),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (hasReport)
                    IconButton(
                      tooltip: 'Veli Gözünden Önizle',
                      onPressed: () => _openParentPreview(student),
                      icon: const Icon(
                        Icons.visibility_outlined,
                        size: 19,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: () => _openStudentEditor(student, report),
                    style: FilledButton.styleFrom(
                      backgroundColor: hasReport
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFF4F46E5),
                      foregroundColor:
                          hasReport ? const Color(0xFF4338CA) : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: Icon(
                      hasReport ? Icons.edit_rounded : Icons.add_rounded,
                      size: 16,
                    ),
                    label: Text(
                      hasReport ? 'Düzenle' : 'Karne Gir',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Hızlı Tek Dokunuş Öğün / Uyku / Duygu Chip'leri (Toplu giriş sonrası anında istisna değiştirme!)
              Builder(
                builder: (_) {
                  final studentCfg = _config.forSchoolType(
                    student.schoolTypeId.isNotEmpty
                        ? student.schoolTypeId
                        : _activeScopeSchoolTypeId,
                  );
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (studentCfg.trackMeals) ...[
                        _buildQuickMealPopupChip(
                          label: 'Kahvaltı',
                          icon: Icons.wb_twilight_rounded,
                          entry: report?.breakfast ?? const MealEntryModel(),
                          onSelected: (status) =>
                              _service.quickPatchStudentReport(
                            institutionId: _institutionId,
                            schoolDocId: _schoolDocId,
                            student: student,
                            dateKey: _dateKey,
                            existing: report,
                            actorUid: _actorUid,
                            actorName: _actorName,
                            breakfast:
                                (report?.breakfast ?? const MealEntryModel())
                                    .copyWith(status: status),
                          ),
                        ),
                        _buildQuickMealPopupChip(
                          label: 'Öğle',
                          icon: Icons.lunch_dining_rounded,
                          entry: report?.lunch ?? const MealEntryModel(),
                          onSelected: (status) =>
                              _service.quickPatchStudentReport(
                            institutionId: _institutionId,
                            schoolDocId: _schoolDocId,
                            student: student,
                            dateKey: _dateKey,
                            existing: report,
                            actorUid: _actorUid,
                            actorName: _actorName,
                            lunch: (report?.lunch ?? const MealEntryModel())
                                .copyWith(status: status),
                          ),
                        ),
                        _buildQuickMealPopupChip(
                          label: 'İkindi',
                          icon: Icons.bakery_dining_rounded,
                          entry: report?.snack ?? const MealEntryModel(),
                          onSelected: (status) =>
                              _service.quickPatchStudentReport(
                            institutionId: _institutionId,
                            schoolDocId: _schoolDocId,
                            student: student,
                            dateKey: _dateKey,
                            existing: report,
                            actorUid: _actorUid,
                            actorName: _actorName,
                            snack: (report?.snack ?? const MealEntryModel())
                                .copyWith(status: status),
                          ),
                        ),
                      ],
                      if (studentCfg.trackSleep)
                        _buildQuickSleepPopupChip(
                          sleep: report?.sleep ?? const SleepEntryModel(),
                          onSelected: (status) =>
                              _service.quickPatchStudentReport(
                            institutionId: _institutionId,
                            schoolDocId: _schoolDocId,
                            student: student,
                            dateKey: _dateKey,
                            existing: report,
                            actorUid: _actorUid,
                            actorName: _actorName,
                            sleep: (report?.sleep ?? const SleepEntryModel())
                                .copyWith(status: status),
                          ),
                        ),
                      if (studentCfg.trackMood)
                        _buildQuickMoodPopupChip(
                          currentMood: report?.mood ?? '',
                          onSelected: (mood) =>
                              _service.quickPatchStudentReport(
                            institutionId: _institutionId,
                            schoolDocId: _schoolDocId,
                            student: student,
                            dateKey: _dateKey,
                            existing: report,
                            actorUid: _actorUid,
                            actorName: _actorName,
                            mood: mood,
                          ),
                        ),
                    ],
                  );
                },
              ),

              // Etkinlik Akışı ve Öğretmen Notu Özeti
              if (report != null &&
                  (report.activities.isNotEmpty ||
                      report.teacherNote.isNotEmpty ||
                      report.neededItems.isNotEmpty ||
                      report.parentFeedbackNote.isNotEmpty)) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),
                if (report.activities.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: report.activities.map((act) {
                      final m = DailyReportCatalog.activityMeta(act.category);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: m.color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${m.emoji} ${act.title}${act.description.isNotEmpty ? ': ${act.description}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: m.color,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                if (report.teacherNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '💌 Not: ${report.teacherNote}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (report.parentFeedbackNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '💬 Veli Yanıtı: "${report.parentFeedbackNote}"',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4338CA),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickMealPopupChip({
    required String label,
    required IconData icon,
    required MealEntryModel entry,
    required ValueChanged<String> onSelected,
  }) {
    final meta = DailyReportCatalog.mealMeta(entry.status);
    final color = meta?.color ?? const Color(0xFF94A3B8);

    return PopupMenuButton<String>(
      tooltip: '$label durumunu hızlı değiştir',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => DailyReportCatalog.mealStatuses
          .map(
            (m) => PopupMenuItem<String>(
              value: m.key,
              child: Row(
                children: [
                  Icon(m.icon, size: 18, color: m.color),
                  const SizedBox(width: 8),
                  Text(
                    '$label: ${m.label}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: meta != null
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: meta != null
                ? color.withValues(alpha: 0.45)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              '$label: ${meta?.shortLabel ?? "Seç"}',
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: meta != null ? color : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSleepPopupChip({
    required SleepEntryModel sleep,
    required ValueChanged<String> onSelected,
  }) {
    final meta = DailyReportCatalog.sleepMeta(sleep.status);
    final color = meta?.color ?? const Color(0xFF94A3B8);

    return PopupMenuButton<String>(
      tooltip: 'Uyku durumunu hızlı değiştir',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => DailyReportCatalog.sleepStatuses
          .map(
            (s) => PopupMenuItem<String>(
              value: s.key,
              child: Row(
                children: [
                  Icon(s.icon, size: 18, color: s.color),
                  const SizedBox(width: 8),
                  Text(
                    'Uyku: ${s.label}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: meta != null
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: meta != null
                ? color.withValues(alpha: 0.45)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bedtime_rounded, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              'Uyku: ${meta?.shortLabel ?? "Seç"}${sleep.durationOrRange.isNotEmpty ? " (${sleep.durationOrRange})" : ""}',
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: meta != null ? color : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickMoodPopupChip({
    required String currentMood,
    required ValueChanged<String> onSelected,
  }) {
    final meta = DailyReportCatalog.moodMeta(currentMood);
    final color = meta?.color ?? const Color(0xFF94A3B8);

    return PopupMenuButton<String>(
      tooltip: 'Duygu durumunu hızlı değiştir',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (_) => DailyReportCatalog.moods
          .map(
            (m) => PopupMenuItem<String>(
              value: m.key,
              child: Text(
                '${m.emoji} ${m.label}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: meta != null
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: meta != null
                ? color.withValues(alpha: 0.45)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              meta?.emoji ?? '🙂',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 5),
            Text(
              meta?.label ?? 'Duygu Seç',
              style: TextStyle(
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: meta != null ? color : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
