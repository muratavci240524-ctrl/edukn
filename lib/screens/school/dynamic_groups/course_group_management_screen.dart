import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

import '../../../models/school/dynamic_course_group_model.dart';
import '../../../services/dynamic_group_service.dart';
import '../../../services/dynamic_group_pdf_service.dart';
import '../../../services/term_service.dart';
import 'club_evaluation_screen.dart';
import 'course_group_edit_screen.dart';

const Color _clubColor = Color(0xFF059669);
const Color _clubLightColor = Color(0xFFD1FAE5);

class CourseGroupManagementScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final DynamicCourseGroupType? initialType;

  const CourseGroupManagementScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialType,
  });

  @override
  State<CourseGroupManagementScreen> createState() => _CourseGroupManagementScreenState();
}

class _CourseGroupManagementScreenState extends State<CourseGroupManagementScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final DynamicGroupService _groupService = DynamicGroupService();

  bool _loading = true;
  String? _activeTermId;
  List<DynamicCourseGroup> _allGroups = [];

  // Sol liste seçim ve arama
  DynamicCourseGroup? _selectedGroup;
  String _searchQuery = '';

  // Yardımcı listeler
  List<Map<String, dynamic>> _workPeriods = [];
  String? _selectedPeriodFilterId;
  List<Map<String, dynamic>> _availableClasses = [];
  List<Map<String, dynamic>> _availableLessons = [];
  List<Map<String, dynamic>> _availableTeachers = [];

  bool get _isSingleType => widget.initialType != null;
  DynamicCourseGroupType get _activeType =>
      widget.initialType ?? (_tabController?.index == 1 ? DynamicCourseGroupType.club : DynamicCourseGroupType.track);

  @override
  void initState() {
    super.initState();
    if (!_isSingleType) {
      _tabController = TabController(length: 2, vsync: this);
      _tabController!.addListener(() {
        if (mounted) setState(() {
          _selectedGroup = null;
        });
      });
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      _activeTermId = selectedTermId ?? activeTermId;

      final instUpper = widget.institutionId.toUpperCase();
      final instLower = widget.institutionId.toLowerCase();

      final classSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      _availableClasses = classSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      final lessonSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      _availableLessons = lessonSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      final teacherSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', whereIn: [instUpper, instLower])
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      _availableTeachers = teacherSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      try {
        Query<Map<String, dynamic>> periodsQuery = FirebaseFirestore.instance
            .collection('workPeriods')
            .where('institutionId', whereIn: [instUpper, instLower])
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true);

        if (_activeTermId != null && _activeTermId!.isNotEmpty) {
          periodsQuery = periodsQuery.where('termId', isEqualTo: _activeTermId);
        }

        final periodSnap = await periodsQuery.get();

        var periods = periodSnap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();

        periods.sort((a, b) {
          final aDate = (a['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bDate = (b['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });

        _workPeriods = periods;
      } catch (pe) {
        debugPrint('Alt dönemler yüklenirken hata: $pe');
      }

      await _refreshGroups();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshGroups() async {
    final groups = await _groupService.fetchGroups(
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      termId: _activeTermId,
    );
    if (mounted) {
      setState(() {
        _allGroups = groups;
      });
    }
  }

  List<DynamicCourseGroup> get _trackGroups =>
      _allGroups.where((g) => g.type == DynamicCourseGroupType.track).toList();

  List<DynamicCourseGroup> get _clubGroups =>
      _allGroups.where((g) => g.type == DynamicCourseGroupType.club).toList();

  Future<void> _navigateToEditScreen({
    required DynamicCourseGroupType type,
    DynamicCourseGroup? existingGroup,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CourseGroupEditScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          type: type,
          existingGroup: existingGroup,
        ),
      ),
    );

    if (result == true) {
      _refreshGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final isTrack = _activeType == DynamicCourseGroupType.track;
    final title = _isSingleType
        ? (isTrack ? 'Kurs Listesi' : 'Kulüp Listesi')
        : 'Kurlar ve Kulüpler';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: title,
        subtitle: widget.schoolTypeName,
        actions: isWide
            ? [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: isTrack ? Colors.indigo.shade600 : _clubColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    isTrack ? 'Yeni Kurs' : 'Yeni Kulüp',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _navigateToEditScreen(type: _activeType),
                ),
                const SizedBox(width: 12),
              ]
            : null,
        bottom: _isSingleType
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: Colors.indigo.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo.shade700,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.layers_outlined, size: 20),
                    text: 'Kurlu Dersler (${_trackGroups.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.sports_soccer_outlined, size: 20),
                    text: 'Kulüpler ve Seçmeli (${_clubGroups.length})',
                  ),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isWide
              ? _buildWideLayout()
              : _buildNarrowLayout(),
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
              backgroundColor: isTrack ? Colors.indigo.shade600 : _clubColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                isTrack ? 'Yeni Kurs' : 'Yeni Kulüp',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _navigateToEditScreen(type: _activeType),
            ),
    );
  }

  // ----------------------------------------------------------------
  // MASAÜSTÜ: Sol liste + Sağ detay layout
  // ----------------------------------------------------------------
  Widget _buildWideLayout() {
    final isTrack = _activeType == DynamicCourseGroupType.track;
    final groups = _isSingleType
        ? (isTrack ? _trackGroups : _clubGroups)
        : (isTrack ? _trackGroups : _clubGroups);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----- SOL PANEL -----
        Container(
          width: 330,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              _buildLeftPanelHeader(),

              Expanded(
                child: _isSingleType
                    ? _buildGroupListPanel(isTrack ? DynamicCourseGroupType.track : DynamicCourseGroupType.club, groups)
                    : _buildTabListPanel(),
              ),
            ],
          ),
        ),
        // ----- SAĞ PANEL -----
        Expanded(
          child: _selectedGroup != null
              ? _buildInlineDetail(_selectedGroup!)
              : _buildEmptyDetailState(),
        ),
      ],
    );
  }

  // MOBİL: Sadece liste, tıklayınca push
  Widget _buildNarrowLayout() {
    final isTrack = _activeType == DynamicCourseGroupType.track;
    final groups = isTrack ? _trackGroups : _clubGroups;
    final type = isTrack ? DynamicCourseGroupType.track : DynamicCourseGroupType.club;

    return Column(
      children: [
        _buildMobilePeriodBar(),

        Expanded(
          child: _isSingleType
              ? _buildGroupList(type, groups)
              : TabBarView(
                  controller: _tabController!,
                  children: [
                    _buildGroupList(DynamicCourseGroupType.track, _trackGroups),
                    _buildGroupList(DynamicCourseGroupType.club, _clubGroups),
                  ],
                ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------
  // SOL PANEL HEADER (Gradient + Arama + Alt Dönem Dropdown)
  // ----------------------------------------------------------------
  Widget _buildLeftPanelHeader() {
    final isTrack = _activeType == DynamicCourseGroupType.track;
    final primaryColor = isTrack ? Colors.indigo.shade600 : const Color(0xFF059669);
    final secondaryColor = isTrack ? Colors.indigo.shade400 : const Color(0xFF10B981);
    final groups = isTrack ? _trackGroups : _clubGroups;
    final effectivePeriodId = _selectedPeriodFilterId ??
        (_workPeriods.isNotEmpty ? _workPeriods.first['id'].toString() : null);

    // Görüntülenecek dönem adı
    String? selectedPeriodName;
    if (effectivePeriodId != null && _workPeriods.isNotEmpty) {
      final match = _workPeriods.firstWhere(
        (p) => p['id'].toString() == effectivePeriodId,
        orElse: () => _workPeriods.first,
      );
      selectedPeriodName = (match['periodName'] ?? match['name'] ?? 'Alt Dönem').toString();
    }

    final displayCount = effectivePeriodId == null
        ? groups.length
        : groups.where((g) =>
            g.periodId == effectivePeriodId ||
            g.termId == effectivePeriodId ||
            g.subTermId == effectivePeriodId).length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve sayaç
          Row(
            children: [
              Icon(
                isTrack ? Icons.layers_outlined : Icons.sports_soccer_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isTrack ? 'Kurslar' : 'Kulüpler',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$displayCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Arama
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: isTrack ? 'Kurs ara...' : 'Kulüp ara...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.white.withValues(alpha: 0.8)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 16, color: Colors.white.withValues(alpha: 0.8)),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          // Alt Dönem Dropdown (ders listesiyle aynı stil)
          if (_workPeriods.isNotEmpty) ...[
            const SizedBox(height: 10),
            Theme(
              data: Theme.of(context).copyWith(cardColor: Colors.white),
              child: PopupMenuButton<String>(
                tooltip: 'Alt Dönem Değiştir',
                offset: const Offset(0, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.amberAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedPeriodName ?? 'Alt Dönem Seç',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
                itemBuilder: (context) => _workPeriods.map((period) {
                  final id = period['id'].toString();
                  final name = (period['periodName'] ?? period['name'] ?? 'Alt Dönem').toString();
                  final isSelected = id == effectivePeriodId;
                  return PopupMenuItem<String>(
                    value: id,
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: isSelected ? (isTrack ? Colors.indigo : const Color(0xFF059669)) : Colors.grey.shade400,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected
                                ? (isTrack ? Colors.indigo.shade900 : const Color(0xFF065F46))
                                : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onSelected: (id) => setState(() => _selectedPeriodFilterId = id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Mobil için kompakt dönem barı (narrow layout altında)
  Widget _buildMobilePeriodBar() {
    if (_workPeriods.isEmpty) return const SizedBox.shrink();
    final effectivePeriodId = _selectedPeriodFilterId ??
        (_workPeriods.isNotEmpty ? _workPeriods.first['id'].toString() : null);
    String? selectedPeriodName;
    if (effectivePeriodId != null) {
      final match = _workPeriods.firstWhere(
        (p) => p['id'].toString() == effectivePeriodId,
        orElse: () => _workPeriods.first,
      );
      selectedPeriodName = (match['periodName'] ?? match['name'] ?? 'Alt Dönem').toString();
    }
    final isTrack = _activeType == DynamicCourseGroupType.track;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, size: 15, color: Colors.indigo.shade600),
          const SizedBox(width: 8),
          const Text(
            'Alt Dönem:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF334155)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(cardColor: Colors.white),
              child: PopupMenuButton<String>(
                tooltip: 'Alt Dönem Değiştir',
                offset: const Offset(0, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          selectedPeriodName ?? 'Seç...',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.indigo.shade700),
                    ],
                  ),
                ),
                itemBuilder: (context) => _workPeriods.map((period) {
                  final id = period['id'].toString();
                  final name = (period['periodName'] ?? period['name'] ?? 'Alt Dönem').toString();
                  final isSelected = id == effectivePeriodId;
                  return PopupMenuItem<String>(
                    value: id,
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: isSelected ? (isTrack ? Colors.indigo : const Color(0xFF059669)) : Colors.grey.shade400,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onSelected: (id) => setState(() => _selectedPeriodFilterId = id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab'lı sol liste paneli (wide + isSingleType=false)
  Widget _buildTabListPanel() {
    if (_tabController == null) return const SizedBox.shrink();
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.indigo.shade700,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: Colors.indigo.shade700,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: [
              Tab(text: 'Kurslar (${_trackGroups.length})'),
              Tab(text: 'Kulüpler (${_clubGroups.length})'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController!,
            children: [
              _buildGroupListPanel(DynamicCourseGroupType.track, _trackGroups),
              _buildGroupListPanel(DynamicCourseGroupType.club, _clubGroups),
            ],
          ),
        ),
      ],
    );
  }

  // Sol paneldeki liste (wide layout için)
  Widget _buildGroupListPanel(DynamicCourseGroupType type, List<DynamicCourseGroup> groups) {
    final effectivePeriodId = _selectedPeriodFilterId ?? (_workPeriods.isNotEmpty ? _workPeriods.first['id'].toString() : null);
    var filtered = effectivePeriodId == null
        ? groups
        : groups.where((g) =>
            g.periodId == effectivePeriodId ||
            g.termId == effectivePeriodId ||
            g.subTermId == effectivePeriodId).toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((g) =>
          g.name.toLowerCase().contains(q) ||
          g.lessonName.toLowerCase().contains(q)).toList();
    }

    final isClub = type == DynamicCourseGroupType.club;
    final primaryColor = isClub ? const Color(0xFF059669) : const Color(0xFF4F46E5);

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isClub ? Icons.sports_soccer_outlined : Icons.layers_outlined,
                size: 48,
                color: primaryColor.withOpacity(0.4),
              ),
              const SizedBox(height: 12),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Arama sonucu bulunamadı'
                    : (isClub ? 'Henüz kulüp yok' : 'Henüz kurs yok'),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _buildListItem(filtered[i], primaryColor),
    );
  }

  // Sol panel liste item (tek tıkla seçim)
  Widget _buildListItem(DynamicCourseGroup group, Color primaryColor) {
    final isSelected = _selectedGroup?.id == group.id;
    final totalStudents = group.subGroups.fold<int>(0, (acc, s) => acc + s.studentIds.length);
    final isClub = group.type == DynamicCourseGroupType.club;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedGroup = group;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.09) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor.withOpacity(0.5) : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // İkon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.18)
                    : primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                color: primaryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            // İsim ve ders adı
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: isSelected ? primaryColor.withOpacity(0.9) : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.book_outlined,
                        size: 11,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          group.lessonName.isNotEmpty ? group.lessonName : (isClub ? 'Kulüp' : 'Kurs'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Öğrenci sayısı badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalStudents',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : primaryColor,
                ),
              ),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: primaryColor),
              ),
          ],
        ),
      ),
    );
  }

  // Sağ panel: Grup seçilmediğinde boş durum
  Widget _buildEmptyDetailState() {
    final isTrack = _activeType == DynamicCourseGroupType.track;
    final primaryColor = isTrack ? Colors.indigo.shade600 : const Color(0xFF059669);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withOpacity(0.12),
                  primaryColor.withOpacity(0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTrack ? Icons.layers_outlined : Icons.sports_soccer_outlined,
              size: 40,
              color: primaryColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isTrack ? 'Kurs Seçin' : 'Kulüp Seçin',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sol listeden bir ${isTrack ? 'kurs' : 'kulüp'} seçerek detayları görüntüleyin.',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Sağ panel: Seçili grubun detayı (inline, Scaffold olmadan)
  Widget _buildInlineDetail(DynamicCourseGroup group) {
    final isClub = group.type == DynamicCourseGroupType.club;
    final primaryColor = isClub ? const Color(0xFF059669) : const Color(0xFF4F46E5);
    final totalStudents = group.subGroups.fold<int>(0, (acc, s) => acc + s.studentIds.length);
    final totalCapacity = group.subGroups.fold<int>(0, (acc, s) => acc + (s.capacity ?? 0));

    return Column(
      children: [
        // Detay AppBar benzeri header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (group.lessonName.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.book_outlined, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            group.lessonName,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Düzenle / Sil menüsü
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'edit') _editGroupInline(group);
                  if (val == 'delete') _deleteGroupInline(group);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Düzenle')]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sil', style: TextStyle(color: Colors.red))
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Detay içeriği
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bilgi kartı
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor.withOpacity(0.07), primaryColor.withOpacity(0.02)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primaryColor.withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'KAPSANAN ŞUBELER',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade500,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 5,
                                  children: group.targetClassNames
                                      .map((cn) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: primaryColor.withOpacity(0.25)),
                                            ),
                                            child: Text(
                                              cn,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: primaryColor,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '$totalStudents',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'öğrenci',
                                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (totalCapacity > 0) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              '$totalStudents / $totalCapacity öğrenci atandı',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${((totalStudents / totalCapacity) * 100).round()}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (totalStudents / totalCapacity).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Alt gruplar başlığı
                Text(
                  isClub ? 'Kulüp Branşları (${group.subGroups.length})' : 'Seviye Kurları (${group.subGroups.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),

                // Alt grup kartları
                ...group.subGroups.map((sub) {
                  final teacherStr = sub.teacherNames.isNotEmpty ? sub.teacherNames.first : 'Öğretmen Yok';
                  final hasCapacity = sub.capacity != null && sub.capacity! > 0;
                  final fillRatio = hasCapacity
                      ? (sub.studentIds.length / sub.capacity!).clamp(0.0, 1.0)
                      : 0.0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: primaryColor.withOpacity(0.12),
                              child: Text(
                                '${sub.studentIds.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        sub.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      if (sub.shortName.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: primaryColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            sub.shortName,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    teacherStr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (sub.classroomName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.room_outlined, size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(sub.classroomName,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                        if (hasCapacity) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                '${sub.studentIds.length}/${sub.capacity}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: fillRatio >= 1.0
                                      ? Colors.red.shade700
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: fillRatio,
                                    minHeight: 4,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      fillRatio >= 1.0
                                          ? Colors.red.shade400
                                          : fillRatio >= 0.8
                                              ? Colors.orange.shade400
                                              : primaryColor.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 28),

                // Aksiyon butonları
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    icon: const Icon(Icons.people_alt_rounded, size: 20),
                    label: Text(
                      isClub ? 'Öğrenci Dağıtım Masası (Kulüplere Ata)' : 'Öğrenci Dağıtım Masası (Kurlara Ata)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () => _openStudentAssignmentFor(group),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                    label: const Text('Şube Çizelgeleri (PDF)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    onPressed: () => _showClassDistributionPickerFor(group),
                  ),
                ),
                if (isClub) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade800,
                        side: BorderSide(color: Colors.amber.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.star_outline_rounded, size: 20),
                      label: const Text('Kulüp Değerlendirmesi',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClubEvaluationScreen(
                            group: group,
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            termId: _activeTermId ?? '',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _editGroupInline(DynamicCourseGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseGroupEditScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          type: group.type,
          existingGroup: group,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _refreshGroups();
        setState(() => _selectedGroup = null);
      }
    });
  }

  void _deleteGroupInline(DynamicCourseGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Grubu Sil'),
        content: Text('${group.name} grubunu kalıcı olarak silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(ctx);
              await DynamicGroupService().deleteGroup(group.id);
              _refreshGroups();
              if (mounted) setState(() => _selectedGroup = null);
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  void _openStudentAssignmentFor(DynamicCourseGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentAssignmentTableScreen(
          group: group,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          onSaved: _refreshGroups,
        ),
      ),
    );
  }

  void _showClassDistributionPickerFor(DynamicCourseGroup group) {
    final isClub = group.type == DynamicCourseGroupType.club;
    final primaryColor = isClub ? const Color(0xFF059669) : const Color(0xFF4F46E5);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Şube Dağılım Çizelgesi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Hangi şubenin çizelgesini yazdırmak istiyorsunuz?',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            const SizedBox(height: 14),
            ...group.targetClassIds.asMap().entries.map((entry) {
              final cId = entry.value;
              final cName = group.targetClassNames.length > entry.key
                  ? group.targetClassNames[entry.key]
                  : cId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: primaryColor.withOpacity(0.12),
                  child:
                      Icon(Icons.school_outlined, color: primaryColor, size: 18),
                ),
                title: Text('$cName Şubesi',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing:
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _printClassDistributionFor(group, cId, cName);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _printClassDistributionFor(
      DynamicCourseGroup group, String classId, String className) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();
      final students = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
      students.sort((a, b) {
        final nameA = '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim();
        final nameB = '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'.trim();
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });
      final pdfBytes = await DynamicGroupPdfService().generateClassDistributionPdf(
        className: className,
        group: group,
        classStudents: students,
        schoolName: widget.schoolTypeName,
      );
      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(
          onLayout: (_) => pdfBytes, name: '${className}_Dagitim.pdf');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF Hatası: $e')));
      }
    }
  }

  Widget _buildGroupList(DynamicCourseGroupType type, List<DynamicCourseGroup> groups) {
    final effectivePeriodFilterId = _selectedPeriodFilterId ?? (_workPeriods.isNotEmpty ? _workPeriods.first['id'].toString() : null);
    final filteredGroups = effectivePeriodFilterId == null
        ? groups
        : groups.where((g) => g.periodId == effectivePeriodFilterId || g.termId == effectivePeriodFilterId || g.subTermId == effectivePeriodFilterId).toList();

    final isClub = type == DynamicCourseGroupType.club;
    final primaryColor = isClub ? _clubColor : const Color(0xFF4F46E5);

    if (filteredGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.12),
                      primaryColor.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isClub ? Icons.sports_soccer_outlined : Icons.layers_outlined,
                  size: 44,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isClub ? 'Henüz Kulüp Grubu Yok' : 'Henüz Kurs Tanımlanmamış',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                isClub
                    ? 'Futsal, Yüzme, Robotik gibi branşları gruplandırmak için kulüp grubu oluşturun.'
                    : 'Şubelerinizin derse aynı anda giren öğrencilerini seviyelere göre kurlara ayırın.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                ),
                icon: const Icon(Icons.add_rounded, size: 22),
                label: Text(
                  isClub ? 'Kulüp Grubu Oluştur' : 'Yeni Kurs Oluştur',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () => _navigateToEditScreen(type: type),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final crossAxisCount = constraints.maxWidth > 1100 ? 3 : (isWide ? 2 : 1);

        if (crossAxisCount == 1) {
          // Mobil: tek sütun liste
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: filteredGroups.length,
            itemBuilder: (context, index) => _buildGroupCard(filteredGroups[index]),
          );
        }

        // Web: multi-column grid
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.45,
          ),
          itemCount: filteredGroups.length,
          itemBuilder: (context, index) => _buildGroupCard(filteredGroups[index]),
        );
      },
    );
  }

  Widget _buildGroupCard(DynamicCourseGroup group) {
    final isClub = group.type == DynamicCourseGroupType.club;
    final primaryColor = isClub ? const Color(0xFF059669) : const Color(0xFF4F46E5);
    final totalStudents = group.subGroups.fold<int>(0, (acc, s) => acc + s.studentIds.length);
    final totalCapacity = group.subGroups.fold<int>(0, (acc, s) => acc + (s.capacity ?? 0));
    final hasCapacity = totalCapacity > 0;
    final fillRatio = hasCapacity ? (totalStudents / totalCapacity).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _CourseGroupDetailScreen(
              group: group,
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
              activeTermId: _activeTermId,
              onRefresh: _refreshGroups,
              availableTeachers: _availableTeachers,
              availableClasses: _availableClasses,
              availableLessons: _availableLessons,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Renkli üst şerit + ikon
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.10),
                      primaryColor.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border(bottom: BorderSide(color: primaryColor.withValues(alpha: 0.12))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.book_outlined, size: 12, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  group.lessonName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ),
                            ],
                          ),
                          if (group.periodName != null && group.periodName!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  group.periodName!,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Ok ikonu â€” tıklanabilirlik ipucu
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: primaryColor.withValues(alpha: 0.6)),
                  ],
                ),
              ),

              // Şube Chip'leri
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kapsanan Şubeler',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: group.targetClassNames.map((cn) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          cn,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Alt bilgi: kur sayısı + öğrenci sayısı + progress
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${group.subGroups.length} ${isClub ? 'Branş' : 'Kur'}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.people_outline_rounded, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          hasCapacity ? '$totalStudents / $totalCapacity' : '$totalStudents öğrenci',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    if (hasCapacity) ...[
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fillRatio,
                          minHeight: 5,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            fillRatio >= 1.0
                                ? Colors.red.shade500
                                : fillRatio >= 0.8
                                    ? Colors.orange.shade500
                                    : primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// -------------------------------------------------------------
// KURS DETAY SAYFASI
// -------------------------------------------------------------
// -------------------------------------------------------------
// KURS DETAY SAYFASI
// -------------------------------------------------------------
class _CourseGroupDetailScreen extends StatelessWidget {
  final DynamicCourseGroup group;
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String? activeTermId;
  final VoidCallback onRefresh;
  final List<Map<String, dynamic>> availableTeachers;
  final List<Map<String, dynamic>> availableClasses;
  final List<Map<String, dynamic>> availableLessons;

  const _CourseGroupDetailScreen({
    required this.group,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.activeTermId,
    required this.onRefresh,
    required this.availableTeachers,
    required this.availableClasses,
    required this.availableLessons,
  });

  Color get _primaryColor =>
      group.type == DynamicCourseGroupType.club ? const Color(0xFF059669) : const Color(0xFF4F46E5);

  bool get _isClub => group.type == DynamicCourseGroupType.club;

  void _openStudentAssignment(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentAssignmentTableScreen(
          group: group,
          institutionId: institutionId,
          schoolTypeId: schoolTypeId,
          onSaved: onRefresh,
        ),
      ),
    );
  }

  void _editGroup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseGroupEditScreen(
          institutionId: institutionId,
          schoolTypeId: schoolTypeId,
          schoolTypeName: schoolTypeName,
          type: group.type,
          existingGroup: group,
        ),
      ),
    ).then((result) {
      if (result == true) {
        onRefresh();
        Navigator.pop(context);
      }
    });
  }

  void _deleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Grubu Sil'),
        content: Text('${group.name} grubunu kalıcı olarak silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(ctx);
              await DynamicGroupService().deleteGroup(group.id);
              onRefresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  void _printSubGroupRoster(BuildContext context, DynamicSubGroup subGroup) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final students = await DynamicGroupService().loadStudentsForSubGroup(
        subGroup: subGroup,
        institutionId: institutionId,
        schoolTypeId: schoolTypeId,
      );
      final pdfBytes = await DynamicGroupPdfService().generateSubGroupRosterPdf(
        group: group,
        subGroup: subGroup,
        students: students,
        schoolName: schoolTypeName,
      );
      if (context.mounted) Navigator.pop(context);
      await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: '${subGroup.name}_Yoklama.pdf');
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Hatası: $e')));
      }
    }
  }

  void _showClassDistributionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Şube Dağılım Çizelgesi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Hangi şubenin çizelgesini yazdırmak istiyorsunuz?',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
            const SizedBox(height: 14),
            ...group.targetClassIds.asMap().entries.map((entry) {
              final cId = entry.value;
              final cName = group.targetClassNames.length > entry.key ? group.targetClassNames[entry.key] : cId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _primaryColor.withValues(alpha: 0.12),
                  child: Icon(Icons.school_outlined, color: _primaryColor, size: 18),
                ),
                title: Text('$cName Şubesi', style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () async {
                  Navigator.pop(ctx);
                  _printClassDistribution(context, cId, cName);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _printClassDistribution(BuildContext context, String classId, String className) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();
      final students = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
      students.sort((a, b) {
        final nameA = '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim();
        final nameB = '${b['firstName'] ?? ''} ${b['lastName'] ?? ''}'.trim();
        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
      });
      final pdfBytes = await DynamicGroupPdfService().generateClassDistributionPdf(
        className: className,
        group: group,
        classStudents: students,
        schoolName: schoolTypeName,
      );
      if (context.mounted) Navigator.pop(context);
      await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: '${className}_Dagitim.pdf');
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Hatası: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final totalStudents = group.subGroups.fold<int>(0, (acc, s) => acc + s.studentIds.length);
    final totalCapacity = group.subGroups.fold<int>(0, (acc, s) => acc + (s.capacity ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: group.name,
        subtitle: _isClub ? 'Kulüp Grubu Detayı' : 'Kurs Grubu Detayı',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'edit') _editGroup(context);
              if (val == 'delete') _deleteGroup(context);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Düzenle')]),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Sil', style: TextStyle(color: Colors.red))
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BİLGİ KARTI ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor.withValues(alpha: 0.08), _primaryColor.withValues(alpha: 0.02)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _primaryColor.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                          color: _primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.name,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.book_outlined, size: 13, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(group.lessonName, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                                if (group.periodName != null && group.periodName!.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _primaryColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      group.periodName!,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primaryColor),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Öğrenci sayısı rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$totalStudents',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'öğrenci',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Şubeler
                  Text(
                    'KAPSANAN ŞUBELER',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.7),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: group.targetClassNames.map((cn) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _primaryColor.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        cn,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _primaryColor),
                      ),
                    )).toList(),
                  ),
                  if (totalCapacity > 0) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '$totalStudents / $totalCapacity öğrenci atandı',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                        const Spacer(),
                        Text(
                          '${((totalStudents / totalCapacity) * 100).round()}%',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (totalStudents / totalCapacity).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // --- KUR / BRANŞ KARTLARI ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isClub ? 'Kulüp Branşları (${group.subGroups.length})' : 'Seviye Kurları (${group.subGroups.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 560 ? 2 : 1);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: isMobile ? 2.8 : 2.2,
                  ),
                  itemCount: group.subGroups.length,
                  itemBuilder: (context, i) {
                    final sub = group.subGroups[i];
                    final teacherStr = sub.teacherNames.isNotEmpty ? sub.teacherNames.first : 'Öğretmen Yok';
                    final hasCapacity = sub.capacity != null && sub.capacity! > 0;
                    final fillRatio = hasCapacity
                        ? (sub.studentIds.length / sub.capacity!).clamp(0.0, 1.0)
                        : 0.0;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _primaryColor.withValues(alpha: 0.12),
                                child: Text(
                                  '${sub.studentIds.length}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          sub.name,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                        ),
                                        if (sub.shortName.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: _primaryColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              sub.shortName,
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _primaryColor),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      teacherStr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              // Yoklama PDF butonu
                              IconButton(
                                icon: Icon(Icons.print_outlined, size: 18, color: Colors.grey.shade600),
                                tooltip: 'Yoklama Listesi PDF',
                                onPressed: () => _printSubGroupRoster(context, sub),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ],
                          ),
                          if (sub.classroomName.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.room_outlined, size: 12, color: Colors.grey.shade500),
                                const SizedBox(width: 3),
                                Text(sub.classroomName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          ],
                          if (hasCapacity) ...[
                            const Spacer(),
                            Row(
                              children: [
                                Text(
                                  '${sub.studentIds.length}/${sub.capacity}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: fillRatio >= 1.0 ? Colors.red.shade700 : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: fillRatio,
                                      minHeight: 4,
                                      backgroundColor: Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        fillRatio >= 1.0
                                            ? Colors.red.shade400
                                            : fillRatio >= 0.8
                                                ? Colors.orange.shade400
                                                : _primaryColor.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 32),

            // --- AKSİYON BUTONLARI ---
            if (isMobile) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.people_alt_rounded, size: 22),
                  label: Text(
                    _isClub ? 'Öğrenci Dağıtım Masası (Kulüplere Ata)' : 'Öğrenci Dağıtım Masası (Kurlara Ata)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  onPressed: () => _openStudentAssignment(context),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                  label: const Text('Şube Çizelgeleri (PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  onPressed: () => _showClassDistributionPicker(context),
                ),
              ),
              if (_isClub) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber.shade800,
                      side: BorderSide(color: Colors.amber.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.star_outline_rounded, size: 20),
                    label: const Text('Kulüp Değerlendirmesi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClubEvaluationScreen(
                          group: group,
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                          termId: activeTermId ?? '',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.people_alt_rounded, size: 22),
                      label: Text(
                        _isClub ? 'Öğrenci Dağıtım Masası' : 'Öğrenci Dağıtım Masası',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      onPressed: () => _openStudentAssignment(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                      label: const Text('Şube Çizelgeleri', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => _showClassDistributionPicker(context),
                    ),
                  ),
                  if (_isClub) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade800,
                        side: BorderSide(color: Colors.amber.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      ),
                      icon: const Icon(Icons.star_outline_rounded, size: 20),
                      label: const Text('Değerlendirme', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClubEvaluationScreen(
                            group: group,
                            institutionId: institutionId,
                            schoolTypeId: schoolTypeId,
                            termId: activeTermId ?? '',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// ÖĞRENCİ DAĞITIM MASASI TAM EKRAN WIDGETI
// -------------------------------------------------------------

class _StudentAssignmentTableScreen extends StatefulWidget {
  final DynamicCourseGroup group;
  final String institutionId;
  final String schoolTypeId;
  final VoidCallback onSaved;

  const _StudentAssignmentTableScreen({
    required this.group,
    required this.institutionId,
    required this.schoolTypeId,
    required this.onSaved,
  });

  @override
  State<_StudentAssignmentTableScreen> createState() => _StudentAssignmentTableScreenState();
}

class _StudentAssignmentTableScreenState extends State<_StudentAssignmentTableScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _allStudents = [];
  late List<DynamicSubGroup> _subGroups;

  String? _selectedClassFilter;
  String? _activeSubGroupId;
  String _statusFilter = 'all'; // 'all', 'active_kur', 'unassigned', 'other_kur'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _subGroups = widget.group.subGroups.map((g) => g.copyWith()).toList();
    if (_subGroups.isNotEmpty) {
      _activeSubGroupId = _subGroups.first.id;
    }
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getStudentFullName(Map<String, dynamic> s) {
    final fn = (s['fullName'] ?? '').toString().trim();
    if (fn.isNotEmpty) return fn;
    final name = (s['name'] ?? s['firstName'] ?? '').toString().trim();
    final surname = (s['surname'] ?? s['lastName'] ?? '').toString().trim();
    final combined = '$name $surname'.trim();
    if (combined.isNotEmpty) return combined;
    final alt = (s['studentName'] ?? s['displayName'] ?? '').toString().trim();
    if (alt.isNotEmpty) return alt;
    final no = (s['studentNumber'] ?? s['studentNo'] ?? s['number'] ?? '').toString().trim();
    return no.isNotEmpty ? 'Öğrenci ($no)' : 'İsimsiz Öğrenci';
  }

  String _getStudentNo(Map<String, dynamic> s) {
    final no = (s['studentNumber'] ?? s['studentNo'] ?? s['number'] ?? '').toString().trim();
    return no.isNotEmpty ? no : '-';
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    try {
      final List<Map<String, dynamic>> loaded = [];
      for (var cId in widget.group.targetClassIds) {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', isEqualTo: cId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          loaded.add(data);
        }
      }

      loaded.sort((a, b) {
        final nameA = _getStudentFullName(a).toLowerCase();
        final nameB = _getStudentFullName(b).toLowerCase();
        return nameA.compareTo(nameB);
      });

      setState(() {
        _allStudents = loaded;
      });
    } catch (e) {
      debugPrint('Error loading students for assignment: $e');
    } finally {
      setState(() => _loading = false);
    }
  }



  Future<void> _autoSave() async {
    try {
      final updatedGroup = widget.group.copyWith(subGroups: _subGroups);
      await DynamicGroupService().saveGroup(updatedGroup);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Otomatik kayıt hatası: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  void _assignSelectedStudents(String targetSubGroupId) {
    if (_selectedStudentIds.isEmpty) return;
    setState(() {
      for (var i = 0; i < _subGroups.length; i++) {
        final sub = _subGroups[i];
        final updatedList = List<String>.from(sub.studentIds)
          ..removeWhere((id) => _selectedStudentIds.contains(id));
        if (sub.id == targetSubGroupId) {
          updatedList.addAll(_selectedStudentIds);
        }
        _subGroups[i] = sub.copyWith(studentIds: updatedList);
      }
      _selectedStudentIds.clear();
    });
    _autoSave();
    final targetSub = _subGroups.firstWhere((s) => s.id == targetSubGroupId, orElse: () => _subGroups.first);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Seçilenler ${targetSub.name} grubuna atandı.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _unassignSelectedStudents() {
    if (_selectedStudentIds.isEmpty) return;
    setState(() {
      for (var i = 0; i < _subGroups.length; i++) {
        final sub = _subGroups[i];
        final updatedList = List<String>.from(sub.studentIds)
          ..removeWhere((id) => _selectedStudentIds.contains(id));
        _subGroups[i] = sub.copyWith(studentIds: updatedList);
      }
      _selectedStudentIds.clear();
    });
    _autoSave();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('✅ Seçilen öğrencilerin ataması kaldırıldı.'),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }



  String? _findSubGroupForStudent(String studentId) {
    for (var sub in _subGroups) {
      if (sub.studentIds.contains(studentId)) {
        return sub.id;
      }
    }
    return null;
  }

  DynamicSubGroup? _getSubGroupById(String? subId) {
    if (subId == null) return null;
    for (var sub in _subGroups) {
      if (sub.id == subId) return sub;
    }
    return null;
  }

  int _matchAndSelectStudentsFromPastedText(String text, {bool autoAssignToActive = false}) {
    if (text.trim().isEmpty) return 0;

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return 0;

    final Set<String> matchedIds = {};

    for (final line in lines) {
      final cells = line.split('\t').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
      final tokensToTest = <String>[line, ...cells];

      for (final s in _allStudents) {
        final sId = s['id']?.toString() ?? '';
        if (sId.isEmpty) continue;

        final fullNameNorm = _normalize(_getStudentFullName(s));
        final noNorm = _normalize(_getStudentNo(s));
        final nameOnlyNorm = _normalize((s['name'] ?? s['firstName'] ?? '').toString());
        final surnameOnlyNorm = _normalize((s['surname'] ?? s['lastName'] ?? '').toString());

        bool matched = false;

        for (final token in tokensToTest) {
          final tNorm = _normalize(token);
          if (tNorm.isEmpty) continue;

          // Eşleşme kontrolü: Tam ad, numara veya ad-soyad kombinasyonu
          if (fullNameNorm == tNorm ||
              (tNorm.length >= 3 && (fullNameNorm.contains(tNorm) || tNorm.contains(fullNameNorm))) ||
              (noNorm.isNotEmpty && noNorm == tNorm) ||
              (nameOnlyNorm.isNotEmpty && surnameOnlyNorm.isNotEmpty && '$nameOnlyNorm $surnameOnlyNorm' == tNorm) ||
              (surnameOnlyNorm.isNotEmpty && nameOnlyNorm.isNotEmpty && '$surnameOnlyNorm $nameOnlyNorm' == tNorm)) {
            matched = true;
            break;
          }
        }

        if (matched) {
          matchedIds.add(sId);
        }
      }
    }

    if (matchedIds.isNotEmpty) {
      if (autoAssignToActive && _activeSubGroupId != null) {
        setState(() {
          for (var i = 0; i < _subGroups.length; i++) {
            final sub = _subGroups[i];
            final updatedList = List<String>.from(sub.studentIds)
              ..removeWhere((id) => matchedIds.contains(id));
            if (sub.id == _activeSubGroupId) {
              updatedList.addAll(matchedIds);
            }
            _subGroups[i] = sub.copyWith(studentIds: updatedList);
          }
          _selectedStudentIds.clear();
        });
      } else {
        setState(() {
          _selectedStudentIds.addAll(matchedIds);
        });
      }
    }

    return matchedIds.length;
  }

  void _showExcelPasteDialog() {
    final textController = TextEditingController();
    final activeSub = _getSubGroupById(_activeSubGroupId);
    final isMobile = MediaQuery.of(context).size.width < 650;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Excel\'den Toplu Seçim', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Ad-soyad veya numara listesini yapıştırın', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.indigo.shade600),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Excel\'deki ad-soyad veya numara sütununu kopyalayıp buraya doğrudan yapıştırın. Sistem tüm öğrencileri otomatik eşleştirecektir.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 7,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                  decoration: InputDecoration(
                    hintText: 'Örnek:\nAhmet Yılmaz\nAyşe Demir\n161\n463\n...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.indigo.shade600, width: 2),
                    ),
                  ),
                ),
                if (activeSub != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: Colors.indigo.shade600),
                        const SizedBox(width: 6),
                        Text(
                          'Hedef Kur: ${activeSub.name}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (activeSub != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_task_rounded, size: 18),
                    label: Text('Eşle ve ${activeSub.name}\'a Doğrudan Ata', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    onPressed: () {
                      final count = _matchAndSelectStudentsFromPastedText(textController.text, autoAssignToActive: true);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('ğŸ‰ $count öğrenci başarıyla ${activeSub.name} grubuna atandı!'),
                          backgroundColor: Colors.green.shade700,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('Sadece Listede Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    final count = _matchAndSelectStudentsFromPastedText(textController.text, autoAssignToActive: false);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('âœ… $count öğrenci eşleşti ve seçildi.'),
                        backgroundColor: Colors.indigo.shade700,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // Masaüstü Dialog Görünümü
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Excel\'den Toplu Öğrenci Seç', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Ad soyad veya numaraları alt alta yapıştırın', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Excel\'de ad-soyad veya numara sütununu kopyalayıp buraya doğrudan yapıştırın. Sistem hedef şubelerdeki öğrencilerle otomatik eşleştirecektir.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 8,
                style: const TextStyle(fontSize: 13, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Örnek:\nAhmet Yılmaz\nAyşe Demir\n161\n463\n...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.indigo.shade600, width: 2),
                  ),
                ),
              ),
              if (activeSub != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 16, color: Colors.indigo.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Aktif Hedef Kur: ${activeSub.name}',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: const Text('Sadece Eşle & Seç'),
            onPressed: () {
              final count = _matchAndSelectStudentsFromPastedText(textController.text, autoAssignToActive: false);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('âœ… $count öğrenci eşleşti ve seçildi.'),
                  backgroundColor: Colors.indigo.shade700,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          if (activeSub != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: Text('Eşle ve ${activeSub.name}\'a Ata'),
              onPressed: () {
                final count = _matchAndSelectStudentsFromPastedText(textController.text, autoAssignToActive: true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('ğŸ‰ $count öğrenci başarıyla ${activeSub.name} grubuna atandı!'),
                    backgroundColor: Colors.green.shade700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }



  void _showPrintMenu(BuildContext context, DynamicSubGroup? activeSub) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yazdır / Dışa Aktar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Hangi listeyi yazdırmak istiyorsunuz?', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const Divider(height: 20),
            ..._subGroups.map((sub) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.indigo.shade50,
                child: Text(
                  '${sub.studentIds.length}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700),
                ),
              ),
              title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${sub.studentIds.length} öğrenci', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.print_outlined, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _printSubGroupRoster(sub);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _printSubGroupRoster(DynamicSubGroup subGroup) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final students = await DynamicGroupService().loadStudentsForSubGroup(
        subGroup: subGroup,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );
      final pdfBytes = await DynamicGroupPdfService().generateSubGroupRosterPdf(
        group: widget.group,
        subGroup: subGroup,
        students: students,
        schoolName: '',
      );
      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: '${subGroup.name}_Yoklama.pdf');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Hatası: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClub = widget.group.type == DynamicCourseGroupType.club;
    final activeSub = _getSubGroupById(_activeSubGroupId);
    final isMobile = MediaQuery.of(context).size.width < 768;

    final filteredStudents = _allStudents.where((s) {
      final sId = s['id'].toString();
      final assignedSubId = _findSubGroupForStudent(sId);

      // Sınıf filtresi
      if (_selectedClassFilter != null && s['classId'] != _selectedClassFilter) {
        return false;
      }

      // Durum Filtresi
      if (_statusFilter == 'active_kur' && assignedSubId != _activeSubGroupId) {
        return false;
      } else if (_statusFilter == 'unassigned' && assignedSubId != null) {
        return false;
      } else if (_statusFilter == 'other_kur' && (assignedSubId == null || assignedSubId == _activeSubGroupId)) {
        return false;
      }

      // Arama
      if (_searchQuery.isNotEmpty) {
        final fullName = _getStudentFullName(s).toLowerCase();
        final number = _getStudentNo(s).toLowerCase();
        final q = _searchQuery.toLowerCase();
        if (!fullName.contains(q) && !number.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final totalEnrolled = _subGroups.fold<int>(0, (acc, g) => acc + g.studentIds.length);
    final unassignedCount = (_allStudents.length - totalEnrolled).clamp(0, 99999);

    final allFilteredSelected = filteredStudents.isNotEmpty &&
        filteredStudents.every((s) => _selectedStudentIds.contains(s['id'].toString()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: '${widget.group.name} - Dağıtım Masası',
        subtitle: isClub ? 'Kulüp Seçim ve Dağıtım Masası' : 'Seviye Kur Dağıtım Masası',
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Yoklama Listesi Yazdır',
            onPressed: () => _showPrintMenu(context, activeSub),
          ),
          const SizedBox(width: 4),
        ],
      ),


      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. ÜST KURS/KUR KARTLARI (Yatay Kartlar)
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 12, isMobile ? 12 : 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMobile) ...[
                        Row(
                          children: [
                            Icon(isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                                size: 17, color: Colors.indigo.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isClub ? 'Hedef Kulüp Seçin:' : 'Hedef Seviye Kuru Seçin:',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Toplam: ${_allStudents.length}  â€¢  Atanan: $totalEnrolled  â€¢  Atanmamış: $unassignedCount',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Icon(isClub ? Icons.sports_soccer_rounded : Icons.auto_stories_rounded,
                                size: 18, color: Colors.indigo.shade700),
                            const SizedBox(width: 8),
                            Text(
                              isClub ? 'Hedef Kulüp Seçin (Tıklayarak Aktifleştirin):' : 'Hedef Seviye Kuru Seçin (Tıklayarak Aktifleştirin):',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Toplam: ${_allStudents.length} Öğrenci  |  Atanan: $totalEnrolled  |  Atanmamış: $unassignedCount',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _subGroups.map((sub) {
                            final isActive = _activeSubGroupId == sub.id;
                            final currentCount = sub.studentIds.length;
                            final isFull = sub.capacity != null && sub.capacity! > 0 && currentCount >= sub.capacity!;

                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _activeSubGroupId = sub.id;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: isMobile ? 180 : 220,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isClub ? const Color(0xFFFAF5FF) : const Color(0xFFEEF2FF))
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isActive
                                          ? (isClub ? Colors.purple.shade600 : Colors.indigo.shade600)
                                          : const Color(0xFFE2E8F0),
                                      width: isActive ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      if (isActive)
                                        BoxShadow(
                                          color: (isClub ? Colors.purple : Colors.indigo).withOpacity(0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sub.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: isActive
                                                    ? (isClub ? Colors.purple.shade900 : Colors.indigo.shade900)
                                                    : const Color(0xFF1E293B),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isActive)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isClub ? Colors.purple.shade600 : Colors.indigo.shade600,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Text(
                                                'SEÇİLİ',
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.people_outline_rounded,
                                              size: 14,
                                              color: isFull ? Colors.red.shade600 : Colors.grey.shade600),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$currentCount ${sub.capacity != null && sub.capacity! > 0 ? "/ ${sub.capacity}" : ""} Öğrenci',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                              color: isFull ? Colors.red.shade700 : const Color(0xFF334155),
                                            ),
                                          ),
                                          const Spacer(),
                                          if (sub.classroomName.isNotEmpty)
                                            Text(
                                              sub.classroomName,
                                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

                // 2. ARAMA, EXCEL'DEN YAPIŞTIR, ŞUBE VE DURUM FİLTRELERİ
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 10),
                  color: Colors.white,
                  child: Column(
                    children: [
                      // Modern Arama Çubuğu & Butonlar
                      if (isMobile) ...[
                        // Mobil Görünüm: Dikey Düzen
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          onChanged: (val) {
                            if (val.contains('\n') || val.contains('\r') || val.contains('\t')) {
                              final count = _matchAndSelectStudentsFromPastedText(val);
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('âœ… Excel listesinden $count öğrenci otomatik seçildi!'),
                                  backgroundColor: Colors.indigo.shade700,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } else {
                              setState(() => _searchQuery = val);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Öğrenci ara veya Excel listesi yapıştır...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.indigo.shade600),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.indigo.shade600, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Excel Butonu (Mobil)
                              Expanded(
                                flex: 3,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.table_chart_rounded, size: 16),
                                  label: const Text('Excel\'den Toplu Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  onPressed: _showExcelPasteDialog,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Şube Filtresi (Mobil)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String?>(
                                      isExpanded: true,
                                      value: _selectedClassFilter,
                                      hint: const Text('Tüm Şubeler', style: TextStyle(fontSize: 12)),
                                      items: [
                                        const DropdownMenuItem<String?>(value: null, child: Text('Tüm Şubeler', style: TextStyle(fontSize: 12))),
                                        ...widget.group.targetClassIds.asMap().entries.map((e) {
                                          final cId = e.value;
                                          final cName = widget.group.targetClassNames.length > e.key
                                              ? widget.group.targetClassNames[e.key]
                                              : cId;
                                          return DropdownMenuItem<String?>(value: cId, child: Text(cName, style: const TextStyle(fontSize: 12)));
                                        }),
                                      ],
                                      onChanged: (val) => setState(() => _selectedClassFilter = val),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[

                        // Web/Masaüstü Görünüm: Yatay Düzen
                        Row(
                          children: [
                            // Arama Kutusu
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                                onChanged: (val) {
                                  if (val.contains('\n') || val.contains('\r') || val.contains('\t')) {
                                    final count = _matchAndSelectStudentsFromPastedText(val);
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('âœ… Excel listesinden $count öğrenci otomatik bulundu ve seçildi!'),
                                        backgroundColor: Colors.indigo.shade700,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } else {
                                    setState(() => _searchQuery = val);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Öğrenci ara (Ad, soyad, no) veya Excel listesi yapıştır...',
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.indigo.shade600),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.indigo.shade600, width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Excel'den Toplu Seç Butonu
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.table_chart_rounded, size: 18),
                              label: const Text('ğŸ“‹ Excel\'den Toplu Seç', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              onPressed: _showExcelPasteDialog,
                            ),
                            const SizedBox(width: 10),

                            // Şube Filtresi
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: _selectedClassFilter,
                                  hint: const Text('Tüm Şubeler', style: TextStyle(fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('Tüm Şubeler', style: TextStyle(fontSize: 13))),
                                    ...widget.group.targetClassIds.asMap().entries.map((e) {
                                      final cId = e.value;
                                      final cName = widget.group.targetClassNames.length > e.key
                                          ? widget.group.targetClassNames[e.key]
                                          : cId;
                                      return DropdownMenuItem<String?>(value: cId, child: Text(cName, style: const TextStyle(fontSize: 13)));
                                    }),
                                  ],
                                  onChanged: (val) => setState(() => _selectedClassFilter = val),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Durum Filtresi Çipleri (Yatay Kaydırılabilir)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('Tümü (${_allStudents.length})', style: const TextStyle(fontSize: 11.5)),
                              selected: _statusFilter == 'all',
                              onSelected: (_) => setState(() => _statusFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            if (activeSub != null) ...[
                              ChoiceChip(
                                label: Text('Sadece ${activeSub.name} (${activeSub.studentIds.length})', style: const TextStyle(fontSize: 11.5)),
                                selected: _statusFilter == 'active_kur',
                                selectedColor: isClub ? _clubLightColor : Colors.indigo.shade100,
                                onSelected: (_) => setState(() => _statusFilter = 'active_kur'),
                              ),
                              const SizedBox(width: 8),
                            ],
                            ChoiceChip(
                              label: Text('Henüz Atanmayanlar ($unassignedCount)', style: const TextStyle(fontSize: 11.5)),
                              selected: _statusFilter == 'unassigned',
                              selectedColor: Colors.orange.shade100,
                              onSelected: (_) => setState(() => _statusFilter = 'unassigned'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Diğer Kurlara Atananlar', style: TextStyle(fontSize: 11.5)),
                              selected: _statusFilter == 'other_kur',
                              onSelected: (_) => setState(() => _statusFilter = 'other_kur'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. SEÇİM ÇUBUĞU (Temiz & Minimal: Tümünü Seç + Seçili Sayacı)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: allFilteredSelected,
                            activeColor: isClub ? Colors.purple.shade700 : Colors.indigo.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedStudentIds.addAll(filteredStudents.map((s) => s['id'].toString()));
                                } else {
                                  for (var s in filteredStudents) {
                                    _selectedStudentIds.remove(s['id'].toString());
                                  }
                                }
                              });
                            },
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tümünü Seç (${filteredStudents.length} Öğrenci)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                              ),
                              if (_selectedStudentIds.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isClub ? Colors.purple.shade100 : Colors.indigo.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_selectedStudentIds.length} Seçili',
                                    style: TextStyle(
                                      color: isClub ? Colors.purple.shade900 : Colors.indigo.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          if (_selectedStudentIds.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.clear_all_rounded, color: Colors.grey.shade600),
                              tooltip: 'Seçimi Temizle',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _selectedStudentIds.clear()),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),


                // 4. ÖĞRENCİ LİSTESİ (Tıklanabilir Kartlar, Kalabalık Butonlar Yok)
                Expanded(
                  child: filteredStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('Kriterlere uygun öğrenci bulunamadı.', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.all(isMobile ? 10 : 16),
                          itemCount: filteredStudents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final s = filteredStudents[index];
                            final sId = s['id'].toString();
                            final fullName = _getStudentFullName(s);
                            final studentNumber = _getStudentNo(s);
                            final className = (s['className'] ?? '-').toString();

                            final assignedSubId = _findSubGroupForStudent(sId);
                            final assignedSub = _getSubGroupById(assignedSubId);
                            final isAssignedToActive = assignedSubId != null && assignedSubId == _activeSubGroupId;

                            final isChecked = _selectedStudentIds.contains(sId);

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isChecked) {
                                    _selectedStudentIds.remove(sId);
                                  } else {
                                    _selectedStudentIds.add(sId);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10 : 14,
                                  vertical: isMobile ? 10 : 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? (isClub ? Colors.purple.shade50.withOpacity(0.5) : Colors.indigo.shade50.withOpacity(0.6))
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isChecked
                                        ? (isClub ? Colors.purple.shade400 : Colors.indigo.shade400)
                                        : (isAssignedToActive
                                            ? Colors.indigo.shade200
                                            : const Color(0xFFE2E8F0)),
                                    width: isChecked ? 1.8 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isChecked ? 0.04 : 0.02),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // Çoklu Seçim Onay Kutusu
                                    Checkbox(
                                      value: isChecked,
                                      activeColor: isClub ? Colors.purple.shade700 : Colors.indigo.shade700,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedStudentIds.add(sId);
                                          } else {
                                            _selectedStudentIds.remove(sId);
                                          }
                                        });
                                      },
                                    ),

                                    // Öğrenci No Rozeti
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isChecked
                                          ? (isClub ? Colors.purple.shade100 : Colors.indigo.shade100)
                                          : (isAssignedToActive ? Colors.indigo.shade100 : const Color(0xFFF1F5F9)),
                                      child: Text(
                                        studentNumber,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isChecked
                                              ? (isClub ? Colors.purple.shade900 : Colors.indigo.shade900)
                                              : (isAssignedToActive ? Colors.indigo.shade900 : const Color(0xFF334155)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Öğrenci Adı ve Bilgisi (Tıklanabilir ve Geniş Alan)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fullName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isChecked
                                                  ? (isClub ? Colors.purple.shade900 : Colors.indigo.shade900)
                                                  : const Color(0xFF1E293B),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Text(
                                                'Şube: $className',
                                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: assignedSub != null
                                                      ? (isAssignedToActive ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF))
                                                      : const Color(0xFFFFF7ED),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: assignedSub != null
                                                        ? (isAssignedToActive ? const Color(0xFFA7F3D0) : const Color(0xFFC7D2FE))
                                                        : const Color(0xFFFED7AA),
                                                  ),
                                                ),
                                                child: Text(
                                                  assignedSub != null ? 'Kur: ${assignedSub.name}' : 'Henüz Atanmadı',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: assignedSub != null
                                                        ? (isAssignedToActive ? const Color(0xFF047857) : Colors.indigo.shade800)
                                                        : const Color(0xFFC2410C),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Seçim Göstergesi İkonu
                                    if (isChecked)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: isClub ? Colors.purple.shade700 : Colors.indigo.shade700,
                                        size: 22,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),

      // 5. EKRANIN ALTINDA ÇIKAN ATAMA ÇUBUĞU
      bottomNavigationBar: _selectedStudentIds.isEmpty
          ? null
          : Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SafeArea(
                child: Row(
                  children: [


                    // Hedef Kura Ata Butonu (Büyük ve Belirgin)
                    if (activeSub != null)
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: isClub ? Colors.purple.shade700 : Colors.indigo.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.add_task_rounded, size: 20),
                          label: Text(
                            'Seçilenleri ${activeSub.name}\'a Ata',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => _assignSelectedStudents(activeSub.id),
                        ),
                      ),

                    const SizedBox(width: 8),

                    // Kurlardan Çıkar Butonu
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _unassignSelectedStudents,
                      child: const Text('Çıkar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
