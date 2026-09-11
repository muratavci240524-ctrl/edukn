import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/class_model.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../services/seating_pdf_service.dart';
import 'seating_plan_editor_screen.dart';
import 'classroom_layout_editor_screen.dart';
import 'seating_analytics_screen.dart';

class SeatingPlanHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isTeacher;
  final String? teacherId;
  final List<String>? allowedClassIds;

  const SeatingPlanHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher = false,
    this.teacherId,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<SeatingPlanHubScreen> createState() => _SeatingPlanHubScreenState();
}

class _SeatingPlanHubScreenState extends State<SeatingPlanHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: 'Sınıf Oturma Planı',
        subtitle: widget.schoolTypeName,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick Action Cards
                    _buildQuickActionCards(),
                    const SizedBox(height: 20),

                    // Tab Bar
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF5C6BC0),
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: const Color(0xFF5C6BC0),
                        indicatorWeight: 3,
                        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14),
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.event_seat_rounded, size: 20),
                            text: 'Oturma Planları',
                          ),
                          Tab(
                            icon: Icon(Icons.grid_view_rounded, size: 20),
                            text: 'Masa Şablonları',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPlansListTab(),
            _buildLayoutsListTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF5C6BC0),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => _navigateToCreatePlan(),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text('Yeni Oturma Planı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
      ),
    );
  }

  Widget _buildQuickActionCards() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    if (isMobile) {
      return Column(
        children: [
          _buildActionCard(
            title: 'Yeni Oturma Planı',
            subtitle: 'Sürükle-bırak & akıllı tarihsel dağıtım ile yeni plan oluştur',
            icon: Icons.add_circle_outline_rounded,
            gradient: const [Color(0xFF5C6BC0), Color(0xFF3949AB)],
            onTap: () => _navigateToCreatePlan(),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            title: 'Derslik Masa Düzenleri',
            subtitle: 'Grid ızgarasında özel masa ve koridor şablonları tasarla',
            icon: Icons.grid_4x4_rounded,
            gradient: const [Color(0xFF7E57C2), Color(0xFF5E35B1)],
            onTap: () => _navigateToCreateLayout(),
          ),
          const SizedBox(height: 12),
          _buildActionCard(
            title: 'Raporlar & Analitik',
            subtitle: 'Öğrenci koordinat geçmişi, sıra oranları ve ısı haritaları',
            icon: Icons.analytics_rounded,
            gradient: const [Color(0xFF00897B), Color(0xFF00695C)],
            onTap: () => _navigateToAnalytics(),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            title: 'Yeni Oturma Planı',
            subtitle: 'Sürükle-bırak & akıllı tarihsel dağıtım ile yeni plan oluştur',
            icon: Icons.add_circle_outline_rounded,
            gradient: const [Color(0xFF5C6BC0), Color(0xFF3949AB)],
            onTap: () => _navigateToCreatePlan(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
            title: 'Derslik Masa Düzenleri',
            subtitle: 'Grid ızgarasında özel masa ve koridor şablonları tasarla',
            icon: Icons.grid_4x4_rounded,
            gradient: const [Color(0xFF7E57C2), Color(0xFF5E35B1)],
            onTap: () => _navigateToCreateLayout(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
            title: 'Raporlar & Analitik',
            subtitle: 'Öğrenci koordinat geçmişi, sıra oranları ve ısı haritaları',
            icon: Icons.analytics_rounded,
            gradient: const [Color(0xFF00897B), Color(0xFF00695C)],
            onTap: () => _navigateToAnalytics(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  String _planSearchQuery = '';
  int? _selectedLevelFilter; // null = all
  final Set<int> _expandedLevels = {};
  final Set<String> _expandedClassIds = {};

  int _determineClassLevel(ClassModel c) {
    if (c.classLevel > 0) return c.classLevel;
    final match = RegExp(r'^(\d+)').firstMatch(c.className.trim());
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null) return parsed;
    }
    return 0; // Diğer / Özel
  }

  int _determineLevelFromName(String name) {
    final match = RegExp(r'^(\d+)').firstMatch(name.trim());
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  String _getLevelTitle(int level) {
    if (level == 0) return 'Diğer & Hazırlık Şubeleri';
    return '$level. Sınıflar';
  }

  Widget _buildPlansListTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (context, classesSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('seating_plans')
              .where('institutionId', isEqualTo: widget.institutionId)
              .snapshots(),
          builder: (context, plansSnap) {
            if (classesSnap.hasError || plansSnap.hasError) {
              final errStr = (classesSnap.error ?? plansSnap.error).toString();
              if (errStr.contains('permission-denied')) {
                return _buildPermissionDeniedState();
              }
              return Center(child: Text('Hata: ${classesSnap.error ?? plansSnap.error}'));
            }
            if (!classesSnap.hasData || !plansSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var classes = classesSnap.data!.docs.map((d) {
              return ClassModel.fromMap(d.data() as Map<String, dynamic>, d.id);
            }).toList();

            var plans = plansSnap.data!.docs.map((d) {
              return SeatingPlan.fromMap(d.data() as Map<String, dynamic>, d.id);
            }).toList();

            if (widget.allowedClassIds != null) {
              classes = classes.where((c) => widget.allowedClassIds!.contains(c.id)).toList();
              final allowedNames = classes.map((c) => c.className).toSet();
              plans = plans.where((p) =>
                  widget.allowedClassIds!.contains(p.classId) ||
                  allowedNames.contains(p.className)).toList();
            }

            // Sınıflara göre planları eşle
            final Map<String, List<SeatingPlan>> plansByClassId = {};
            final Map<String, List<SeatingPlan>> plansByClassName = {};
            for (var p in plans) {
              if (p.classId.isNotEmpty) {
                plansByClassId.putIfAbsent(p.classId, () => []).add(p);
              }
              if (p.className.isNotEmpty) {
                plansByClassName.putIfAbsent(p.className, () => []).add(p);
              }
            }

            for (var list in plansByClassId.values) {
              list.sort((a, b) => b.planDate.compareTo(a.planDate));
            }
            for (var list in plansByClassName.values) {
              list.sort((a, b) => b.planDate.compareTo(a.planDate));
            }

            // Seviyelere göre sınıfları grupla
            final Map<int, List<ClassModel>> classesByLevel = {};
            for (var c in classes) {
              final lvl = _determineClassLevel(c);
              classesByLevel.putIfAbsent(lvl, () => []).add(c);
            }

            // Eğer classes koleksiyonu boşsa veya eksikse, planlardaki sınıfları da seviyelere ekle
            final seenClassNames = classes.map((c) => c.className).toSet();
            final seenClassIds = classes.map((c) => c.id).toSet();
            for (var p in plans) {
              if (widget.allowedClassIds != null && !widget.allowedClassIds!.contains(p.classId)) {
                continue;
              }
              if (!seenClassIds.contains(p.classId) && !seenClassNames.contains(p.className)) {
                seenClassNames.add(p.className);
                final lvl = _determineLevelFromName(p.className);
                final dummyClass = ClassModel(
                  id: p.classId.isNotEmpty ? p.classId : null,
                  className: p.className,
                  shortName: p.className,
                  classTypeId: '',
                  classTypeName: '',
                  classLevel: lvl,
                  schoolTypeId: widget.schoolTypeId,
                  schoolTypeName: widget.schoolTypeName,
                  institutionId: widget.institutionId,
                  createdAt: DateTime.now(),
                );
                classesByLevel.putIfAbsent(lvl, () => []).add(dummyClass);
              }
            }

            // Sınıfları ada göre sırala
            for (var list in classesByLevel.values) {
              list.sort((a, b) => a.className.compareTo(b.className));
            }

            final sortedLevels = classesByLevel.keys.toList()..sort();

            if (classesByLevel.isEmpty) {
              return _buildEmptyTabState(
                icon: Icons.event_seat_rounded,
                title: 'Henüz Kayıtlı Şube veya Plan Bulunamadı',
                subtitle: 'Sınıflarınız için akıllı dağıtımlı oturma planları oluşturarak başlayın.',
                actionText: 'Yeni Plan Oluştur',
                onAction: () => _navigateToCreatePlan(),
              );
            }

            // Filtreleme (Seviye ve Arama Sorgusu)
            final query = _planSearchQuery.trim().toLowerCase();
            final filteredLevels = sortedLevels.where((lvl) {
              if (_selectedLevelFilter != null && _selectedLevelFilter != lvl) return false;
              if (query.isEmpty) return true;

              final lvlTitle = _getLevelTitle(lvl).toLowerCase();
              if (lvlTitle.contains(query)) return true;

              final classList = classesByLevel[lvl] ?? [];
              for (var c in classList) {
                if (c.className.toLowerCase().contains(query)) return true;
                final cPlans = plansByClassId[c.id] ?? plansByClassName[c.className] ?? [];
                for (var p in cPlans) {
                  if (p.title.toLowerCase().contains(query)) return true;
                }
              }
              return false;
            }).toList();

            final totalBranches = classesByLevel.values.fold<int>(0, (s, l) => s + l.length);
            final totalPlans = plans.length;
            final dateFormat = DateFormat('dd.MM.yyyy');

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                // Arama ve Filtre Çubuğu
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Şube veya plan ara (Örn: 8-A, 801, 7. Sınıf)...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                      suffixIcon: _planSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                              onPressed: () => setState(() => _planSearchQuery = ''),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _planSearchQuery = v),
                  ),
                ),
                const SizedBox(height: 12),

                // Seviye Seçim Çipleri (Yatay Kaydırılabilir)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      // Tümü Çipi
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            'Tümü ($totalBranches Şube • $totalPlans Plan)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: _selectedLevelFilter == null ? FontWeight.bold : FontWeight.w500,
                              color: _selectedLevelFilter == null ? Colors.white : const Color(0xFF475569),
                            ),
                          ),
                          selected: _selectedLevelFilter == null,
                          selectedColor: const Color(0xFF5C6BC0),
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _selectedLevelFilter == null ? const Color(0xFF5C6BC0) : const Color(0xFFE2E8F0),
                          ),
                          onSelected: (_) => setState(() => _selectedLevelFilter = null),
                        ),
                      ),
                      // Her Seviyenin Çipi
                      ...sortedLevels.map((lvl) {
                        final isSelected = _selectedLevelFilter == lvl;
                        final lvlClasses = classesByLevel[lvl] ?? [];
                        int lvlPlansCount = 0;
                        for (var c in lvlClasses) {
                          final cp = plansByClassId[c.id] ?? plansByClassName[c.className] ?? [];
                          lvlPlansCount += cp.length;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${_getLevelTitle(lvl)} (${lvlClasses.length} Şube • $lvlPlansCount Plan)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF5C6BC0),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF5C6BC0) : const Color(0xFFE2E8F0),
                            ),
                            onSelected: (_) => setState(() => _selectedLevelFilter = isSelected ? null : lvl),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (filteredLevels.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aramanızla eşleşen şube veya oturma planı bulunamadı.',
                        style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13.5),
                      ),
                    ),
                  ),

                // Seviye Bazlı Gruplar ve İçindeki Şubeler
                ...filteredLevels.map((lvl) {
                  final lvlTitle = _getLevelTitle(lvl);
                  final lvlClasses = (classesByLevel[lvl] ?? []).where((c) {
                    if (query.isEmpty) return true;
                    if (lvlTitle.toLowerCase().contains(query)) return true;
                    if (c.className.toLowerCase().contains(query)) return true;
                    final cPlans = plansByClassId[c.id] ?? plansByClassName[c.className] ?? [];
                    return cPlans.any((p) => p.title.toLowerCase().contains(query));
                  }).toList();

                  int lvlPlansCount = 0;
                  for (var c in lvlClasses) {
                    final cp = plansByClassId[c.id] ?? plansByClassName[c.className] ?? [];
                    lvlPlansCount += cp.length;
                  }

                  final isLevelExpanded = _expandedLevels.contains(lvl) || query.isNotEmpty || _selectedLevelFilter != null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1E293B).withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Seviye Başlık Kartı (Tıklanabilir Accordion)
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_expandedLevels.contains(lvl)) {
                                _expandedLevels.remove(lvl);
                              } else {
                                _expandedLevels.add(lvl);
                              }
                            });
                          },
                          borderRadius: BorderRadius.vertical(
                            top: const Radius.circular(18),
                            bottom: Radius.circular(isLevelExpanded ? 0 : 18),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(
                                top: const Radius.circular(18),
                                bottom: Radius.circular(isLevelExpanded ? 0 : 18),
                              ),
                              border: isLevelExpanded ? const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))) : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5C6BC0).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.domain_rounded, color: Color(0xFF5C6BC0), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lvlTitle,
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      Text(
                                        '${lvlClasses.length} Şube • $lvlPlansCount Kayıtlı Plan',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          color: const Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isLevelExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFF64748B),
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Seviye Açıkken İçindeki Şubeler
                        if (isLevelExpanded)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: lvlClasses.map((classItem) {
                                final classPlans = plansByClassId[classItem.id] ?? plansByClassName[classItem.className] ?? [];
                                final classKey = classItem.id ?? classItem.className;
                                final isBranchExpanded = _expandedClassIds.contains(classKey) || query.isNotEmpty || classPlans.isNotEmpty;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isBranchExpanded && classPlans.isNotEmpty
                                          ? const Color(0xFFC7D2FE)
                                          : const Color(0xFFE2E8F0),
                                      width: isBranchExpanded && classPlans.isNotEmpty ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Şube Başlık Satırı
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            if (_expandedClassIds.contains(classKey)) {
                                              _expandedClassIds.remove(classKey);
                                            } else {
                                              _expandedClassIds.add(classKey);
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(14),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                          child: Row(
                                            children: [
                                              // Şube Badge
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF5C6BC0),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  classItem.className,
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),

                                              // Şube Bilgisi
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${classItem.className} Şubesi',
                                                      style: GoogleFonts.inter(
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 14,
                                                        color: const Color(0xFF1E293B),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      classPlans.isNotEmpty
                                                          ? '${classPlans.length} Plan  •  Son: ${dateFormat.format(classPlans.first.planDate)}'
                                                          : 'Henüz oturma planı yapılmamış',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11.5,
                                                        color: classPlans.isNotEmpty ? const Color(0xFF4338CA) : Colors.grey.shade500,
                                                        fontWeight: classPlans.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              // Hızlı Yeni Plan Butonu
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFEEF2FF),
                                                  foregroundColor: const Color(0xFF4338CA),
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                                                  ),
                                                ),
                                                onPressed: () => _navigateToCreatePlan(initialClassId: classItem.id),
                                                icon: const Icon(Icons.add_rounded, size: 16),
                                                label: Text('Plan Yap', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                              ),
                                              const SizedBox(width: 4),

                                              if (classPlans.isNotEmpty)
                                                Icon(
                                                  isBranchExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                                  color: const Color(0xFF64748B),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Şube İçi Planlar Listesi
                                      if (isBranchExpanded && classPlans.isNotEmpty)
                                        Container(
                                          decoration: const BoxDecoration(
                                            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                                            color: Colors.white,
                                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                                          ),
                                          padding: const EdgeInsets.all(8),
                                          child: Column(
                                            children: classPlans.map((plan) {
                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: ListTile(
                                                  dense: true,
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                                  leading: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF5C6BC0).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Icon(Icons.event_seat_rounded, color: Color(0xFF5C6BC0), size: 18),
                                                  ),
                                                  title: Text(
                                                    plan.title,
                                                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B)),
                                                  ),
                                                  subtitle: Text(
                                                    '${dateFormat.format(plan.planDate)} • ${plan.assignedStudentCount} Öğrenci (${plan.pinnedStudentCount} Sabit)',
                                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                                  ),
                                                  trailing: PopupMenuButton<String>(
                                                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: Color(0xFF64748B)),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                    onSelected: (val) {
                                                      if (val == 'print') {
                                                        _printPdf(plan);
                                                      } else if (val == 'edit') {
                                                        _navigateToEditPlan(plan);
                                                      } else if (val == 'delete') {
                                                        _deletePlan(plan);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      PopupMenuItem(
                                                        value: 'print',
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding: const EdgeInsets.all(6),
                                                              decoration: BoxDecoration(
                                                                color: const Color(0xFF5C6BC0).withOpacity(0.1),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: const Icon(Icons.print_rounded, size: 16, color: Color(0xFF5C6BC0)),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Text('Yazdır / PDF', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding: const EdgeInsets.all(6),
                                                              decoration: BoxDecoration(
                                                                color: Colors.blue.withOpacity(0.1),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: const Icon(Icons.edit_rounded, size: 16, color: Colors.blue),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Text('Düzenle', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'delete',
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding: const EdgeInsets.all(6),
                                                              decoration: BoxDecoration(
                                                                color: Colors.red.withOpacity(0.1),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Text('Sil', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5, color: Colors.red)),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  onTap: () => _navigateToEditPlan(plan),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLayoutsListTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('seating_layouts')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final errStr = snapshot.error.toString();
          if (errStr.contains('permission-denied')) {
            return _buildPermissionDeniedState();
          }
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final layouts = snapshot.data!.docs
            .map((doc) => ClassroomLayout.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();

        if (layouts.isEmpty) {
          return _buildEmptyTabState(
            icon: Icons.grid_view_rounded,
            title: 'Henüz Masa Şablonu Tanımlanmamış',
            subtitle: 'Özel derslik yerleşim şablonları oluşturarak planlarda hızlıca kullanabilirsiniz.',
            actionText: 'Şablon Oluştur',
            onAction: () => _navigateToCreateLayout(),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
          itemCount: layouts.length,
          itemBuilder: (context, index) {
            final layout = layouts[index];
            return Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7E57C2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.grid_4x4_rounded, color: Color(0xFF7E57C2), size: 24),
                ),
                title: Text(
                  layout.name,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
                subtitle: Text(
                  '${layout.rows}x${layout.cols} • ${layout.totalDeskCount} Masa • ${layout.totalCapacity} Kişilik',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _navigateToEditLayout(layout);
                    } else if (val == 'delete') {
                      _deleteLayout(layout);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                          ),
                          const SizedBox(width: 10),
                          Text('Düzenle', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          ),
                          const SizedBox(width: 10),
                          Text('Sil', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () => _navigateToEditLayout(layout),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyTabState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5C6BC0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(actionText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFCC80), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_update_warning_rounded, size: 36, color: Color(0xFFE65100)),
            ),
            const SizedBox(height: 16),
            Text(
              'Firestore Güvenlik Kuralları İzni Gerekli',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 10),
            Text(
              'Sınıf oturma planı ve masa şablonları için `firestore.rules` dosyasına gerekli güvenlik izinleri eklenmiştir.\n\nFirebase Console -> Firestore Database -> Rules sekmesinden kuralları yayınladığınızda (Publish) oturma planları anında aktifleşecektir.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700, height: 1.45),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                'match /seating_plans/{id} { allow read, write: if request.auth != null; }\nmatch /seating_layouts/{id} { allow read, write: if request.auth != null; }',
                style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFF37474F)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToCreatePlan({String? initialClassId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatingPlanEditorScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          initialClassId: initialClassId,
          allowedClassIds: widget.allowedClassIds,
        ),
      ),
    );
  }

  void _navigateToEditPlan(SeatingPlan plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatingPlanEditorScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          existingPlan: plan,
          allowedClassIds: widget.allowedClassIds,
        ),
      ),
    );
  }

  void _navigateToCreateLayout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassroomLayoutEditorScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  void _navigateToEditLayout(ClassroomLayout layout) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassroomLayoutEditorScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          existingLayout: layout,
        ),
      ),
    );
  }

  void _navigateToAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeatingAnalyticsScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          allowedClassIds: widget.allowedClassIds,
        ),
      ),
    );
  }

  Future<void> _printPdf(SeatingPlan plan) async {
    final bytes = await SeatingPdfService.generateSeatingPlanPdf(plan: plan);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<void> _deletePlan(SeatingPlan plan) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Oturma Planını Sil',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                '"${plan.title}" planını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Vazgeç', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Evet, Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && plan.id != null) {
      await FirebaseFirestore.instance
          .collection('seating_plans')
          .doc(plan.id)
          .delete();
    }
  }

  Future<void> _deleteLayout(ClassroomLayout layout) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFDC2626), size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Masa Şablonunu Sil',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                '"${layout.name}" şablonunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Vazgeç', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Evet, Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true && layout.id != null) {
      await FirebaseFirestore.instance
          .collection('seating_layouts')
          .doc(layout.id)
          .delete();
    }
  }
}
