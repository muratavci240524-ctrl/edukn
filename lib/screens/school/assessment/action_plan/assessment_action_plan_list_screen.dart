import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:intl/intl.dart';
import 'assessment_action_plan_screen.dart';
import 'assessment_action_plan_selection_dialog.dart';
import 'assessment_action_plan_stats_screen.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/user_permission_service.dart';
import '../../../../widgets/edukn_logo.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../../../services/action_plan_report_pdf_service.dart';

class AssessmentActionPlanListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const AssessmentActionPlanListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _AssessmentActionPlanListScreenState createState() => _AssessmentActionPlanListScreenState();
}

class _AssessmentActionPlanListScreenState extends State<AssessmentActionPlanListScreen> {
  final AssessmentService _service = AssessmentService();
  String _selectedClassFilter = 'Tümü';
  bool _showPassive = false;
  String? _userRole;

  late final Stream<List<AssessmentActionPlan>> _plansStream;

  @override
  void initState() {
    super.initState();
    _plansStream = _service.getAssessmentActionPlans(widget.institutionId, widget.schoolTypeId);
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    setState(() => _userRole = 'admin');
  }

  // Helper to get consistent class level across UI and filters
  String _getResolvedLevel(AssessmentActionPlan plan) {
    String level = plan.classLevel.trim();
    if (level == 'Tümü' || level.isEmpty || level == 'GENEL') {
      final Iterable<String> candidateKeys = [
        ...plan.branchActionPlans.keys,
        ...plan.outcomeStats.keys,
      ];
      for (var branchKey in candidateKeys) {
        final branchName = branchKey.split('_').first;
        final match = RegExp(r'^(\d+)').firstMatch(branchName);
        if (match != null) {
          String raw = match.group(1)!;
          if (raw.length == 3) return raw[0];
          if (raw.length == 4) return raw.substring(0, 2);
          return raw;
        }
      }
      return 'GENEL';
    }
    final match = RegExp(r'^(\d+)').firstMatch(level);
    if (match != null) {
      return match.group(1)!;
    }
    return level.replaceAll(RegExp(r'\.?\s*sınıf', caseSensitive: false), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return SafeStreamBuilder<List<AssessmentActionPlan>>(
      stream: _plansStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: EduKnLoader(size: 60)));
        }

        final allPlans = snapshot.data ?? [];
        final activePlans = allPlans.where((p) => !p.isRealized).toList();
        final passivePlans = allPlans.where((p) => p.isRealized).toList();
        final tabPlans = _showPassive ? passivePlans : activePlans;

        // Collect resolved levels for filtering within the selected Aktif/Pasif tab
        final Set<String> levels = tabPlans
            .map((p) => _getResolvedLevel(p))
            .where((l) => l != 'GENEL')
            .toSet();
        final List<String> sortedLevels = [
          'Tümü',
          ...(levels.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0))),
        ];
        final effectiveClassFilter = sortedLevels.contains(_selectedClassFilter)
            ? _selectedClassFilter
            : 'Tümü';

        final filteredPlans = tabPlans.where((p) {
          if (effectiveClassFilter == 'Tümü') return true;
          return _getResolvedLevel(p) == effectiveClassFilter;
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FE),
          appBar: EduknAppBar(
            title: 'Eylem Planları Geçmişi',
            actions: [
              IconButton(
                icon: Icon(Icons.bar_chart_rounded, color: Colors.indigo.shade700),
                tooltip: 'İstatistikler',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AssessmentActionPlanStatsScreen(
                        plans: allPlans,
                        schoolTypeId: widget.schoolTypeId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          floatingActionButton: _userRole != 'teacher'
              ? SizedBox(
                  height: 44,
                  child: FloatingActionButton.extended(
                    onPressed: () => _showSelectionModal(context),
                    backgroundColor: Colors.indigo.shade900,
                    elevation: 3,
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'Yeni Plan Oluştur',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                )
              : null,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final bool isWide = constraints.maxWidth >= 780;
              final bool isMobile = constraints.maxWidth < 600;
              final double hPad = isMobile ? 12.0 : 20.0;

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 2),
                        child: _buildStatusTabs(
                          activeCount: activePlans.length,
                          passiveCount: passivePlans.length,
                        ),
                      ),
                      if (sortedLevels.length > 1)
                        _buildClassFilterBar(sortedLevels, effectiveClassFilter, hPad: hPad)
                      else
                        const SizedBox(height: 8),
                      Expanded(
                        child: filteredPlans.isEmpty
                            ? _buildEmptyState(
                                isPassiveTab: _showPassive,
                                otherTabCount: _showPassive ? activePlans.length : passivePlans.length,
                              )
                            : isWide
                                ? ListView.builder(
                                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 88),
                                    itemCount: (filteredPlans.length + 1) ~/ 2,
                                    itemBuilder: (context, rowIndex) {
                                      final leftIndex = rowIndex * 2;
                                      final rightIndex = leftIndex + 1;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: _buildPlanCard(filteredPlans[leftIndex], bottomMargin: 0),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: rightIndex < filteredPlans.length
                                                  ? _buildPlanCard(filteredPlans[rightIndex], bottomMargin: 0)
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 88),
                                    itemCount: filteredPlans.length,
                                    itemBuilder: (context, index) => _buildPlanCard(filteredPlans[index]),
                                  ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatusTabs({required int activeCount, required int passiveCount}) {
    Widget tab({
      required String label,
      required int count,
      required IconData icon,
      required bool passiveValue,
      required Color activeColor,
    }) {
      final bool isSelected = _showPassive == passiveValue;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_showPassive != passiveValue) {
              setState(() {
                _showPassive = passiveValue;
                _selectedClassFilter = 'Tümü';
              });
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.24),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.22)
                        : const Color(0xFFD9E1EE),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF4),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          tab(
            label: 'Aktif',
            count: activeCount,
            icon: Icons.play_circle_outline_rounded,
            passiveValue: false,
            activeColor: Colors.indigo.shade900,
          ),
          tab(
            label: 'Pasif',
            count: passiveCount,
            icon: Icons.inventory_2_outlined,
            passiveValue: true,
            activeColor: const Color(0xFF475569),
          ),
        ],
      ),
    );
  }

  Widget _buildClassFilterBar(
    List<String> sortedLevels,
    String effectiveClassFilter, {
    double hPad = 16.0,
  }) {
    return Container(
      height: 34,
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        itemCount: sortedLevels.length,
        itemBuilder: (context, index) {
          final level = sortedLevels[index];
          final isSelected = effectiveClassFilter == level;
          final displayLabel = level == 'Tümü'
              ? 'Tüm Planlar'
              : (level.toLowerCase().contains('sınıf') ? level : '$level. Sınıf');

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedClassFilter = level),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [Colors.indigo.shade900, Colors.indigo.shade700])
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.indigo.withValues(alpha: 0.22),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  displayLabel,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.indigo.shade900,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(AssessmentActionPlan plan, {double bottomMargin = 10.0}) {
    final accentColor = plan.isRealized ? Colors.green.shade600 : Colors.indigo.shade700;
    return Container(
      margin: EdgeInsets.only(bottom: bottomMargin),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AssessmentActionPlanScreen(
                  institutionId: widget.institutionId,
                  schoolTypeId: widget.schoolTypeId,
                  existingPlan: plan,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst satır: İkon + Tam görünen başlık (2 satıra kadar) + Kompakt Sil ikonu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        plan.isRealized ? Icons.task_alt_rounded : Icons.analytics_outlined,
                        size: 17,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.title,
                            style: const TextStyle(
                              fontSize: 13.8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildClassBadge(_getResolvedLevel(plan)),
                              _buildStatusChip(plan.isRealized),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 3),
                                  Text(
                                    DateFormat('dd.MM.yyyy HH:mm').format(plan.date),
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 12.5, color: Colors.grey.shade500),
                                  const SizedBox(width: 3),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 140),
                                    child: _buildCreatorText(plan),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Sil',
                        onPressed: () => _showDeleteConfirm(plan.id),
                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 17),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // Kapsanan sınavlar kutusu (kompakt)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.3),
                      children: [
                        const TextSpan(
                          text: 'Sınavlar: ',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                        ),
                        TextSpan(
                          text: plan.selectedExamNames.isNotEmpty
                              ? plan.selectedExamNames.join(', ')
                              : 'Belirtilmemiş',
                        ),
                      ],
                    ),
                  ),
                ),
                if (plan.realizationNotes.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: plan.isRealized ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: plan.isRealized ? Colors.green.shade100 : Colors.amber.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notes_rounded,
                          size: 13.5,
                          color: plan.isRealized ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            plan.realizationNotes.trim(),
                            style: TextStyle(
                              fontSize: 11,
                              color: plan.isRealized ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Alt aksiyon satırı: tek satırda kompakt butonlar
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Planı Aç',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 16, color: Colors.indigo.shade700),
                        ],
                      ),
                    ),
                    _buildCompactActionBtn(
                      onTap: () => _showStatusUpdateDialog(plan),
                      icon: plan.isRealized ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      label: plan.isRealized ? 'Durum' : 'İzleme / Tamamla',
                      bgColor: plan.isRealized ? Colors.green.shade50 : Colors.orange.shade50,
                      fgColor: plan.isRealized ? Colors.green.shade700 : Colors.orange.shade800,
                      borderColor: plan.isRealized ? Colors.green.shade200 : Colors.orange.shade200,
                    ),
                    const SizedBox(width: 6),
                    _buildCompactActionBtn(
                      onTap: () => _generateReport(plan),
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Rapor Al',
                      bgColor: Colors.indigo.shade50,
                      fgColor: Colors.indigo.shade800,
                      borderColor: Colors.indigo.shade100,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactActionBtn({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color fgColor,
    required Color borderColor,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fgColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorText(AssessmentActionPlan plan) {
    final textStyle = TextStyle(color: Colors.grey.shade600, fontSize: 11);
    if (plan.creatorName.isNotEmpty &&
        plan.creatorName != 'Kullanıcı' &&
        plan.creatorName != 'Sistem Yöneticisi' &&
        plan.creatorName != 'anon') {
      return Text(plan.creatorName, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final cached = UserPermissionService.getCachedUserFullName(plan.createdBy);
    if (cached != null && cached != 'Sistem Yöneticisi') {
      return Text(cached, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    return FutureBuilder<String>(
      future: UserPermissionService.resolveUserFullName(plan.createdBy, institutionId: plan.institutionId, fallback: ''),
      builder: (context, snapshot) {
        final name = (snapshot.data != null &&
                snapshot.data!.isNotEmpty &&
                snapshot.data != 'Kullanıcı' &&
                snapshot.data != 'Sistem Yöneticisi')
            ? snapshot.data!
            : (plan.creatorName.isNotEmpty && plan.creatorName != 'Kullanıcı' && plan.creatorName != 'Sistem Yöneticisi'
                ? plan.creatorName
                : '');

        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!.isNotEmpty &&
            snapshot.data != 'Kullanıcı' &&
            snapshot.data != 'Sistem Yöneticisi' &&
            (plan.creatorName == 'Kullanıcı' || plan.creatorName == 'Sistem Yöneticisi' || plan.creatorName.isEmpty)) {
          FirebaseFirestore.instance
              .collection('assessment_action_plans')
              .doc(plan.id)
              .update({'creatorName': snapshot.data})
              .catchError((_) {});
        }
        return Text(
          name.isNotEmpty ? name : 'Yönetici',
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Future<ActionPlanReportMode?> _chooseReportMode() {
    Widget option(BuildContext ctx, IconData icon, String title, String sub, ActionPlanReportMode m) {
      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade50,
          child: Icon(icon, color: Colors.indigo.shade700, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        onTap: () => Navigator.pop(ctx, m),
      );
    }

    return showModalBottomSheet<ActionPlanReportMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text('Rapor Türünü Seçin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              option(ctx, Icons.groups_rounded, 'Sınıf (Şube) Bazlı Rapor',
                  'Her şube ayrı sayfada: kritik kazanımlar ve eylem planları', ActionPlanReportMode.classOnly),
              option(ctx, Icons.person_search_rounded, 'Öğrenci Bazlı Rapor',
                  'Barajın altındaki öğrenciler, görevler ve veli bilgilendirme durumu', ActionPlanReportMode.studentOnly),
              option(ctx, Icons.picture_as_pdf_rounded, 'Tam Rapor',
                  'Sınıf ve öğrenci bazlı bölümlerin ikisi birlikte', ActionPlanReportMode.full),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateReport(AssessmentActionPlan plan) async {
    final mode = await _chooseReportMode();
    if (mode == null || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    Uint8List? bytes;
    try {
      bytes = await ActionPlanReportPdfService.generate(plan, mode: mode);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rapor oluşturulamadı: $e')));
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (bytes != null) {
      final data = bytes;
      await Printing.layoutPdf(
        name: 'Eylem_Plani_Raporu.pdf',
        onLayout: (_) async => data,
      );
    }
  }

  Widget _buildStatusChip(bool isRealized) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isRealized ? Colors.green.withValues(alpha: 0.1) : Colors.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isRealized ? 'GERÇEKLEŞTİ' : 'AKTİF',
        style: TextStyle(
          color: isRealized ? Colors.green.shade700 : Colors.indigo.shade700,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildClassBadge(String level) {
    String display;
    if (level == 'GENEL') {
      display = 'GENEL';
    } else if (level.toUpperCase().contains('SINIF')) {
      display = level.toUpperCase();
    } else {
      display = '$level. SINIF';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.indigo.shade100, width: 0.8),
      ),
      child: Text(
        display,
        style: TextStyle(color: Colors.indigo.shade900, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  void _showSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AssessmentActionPlanSelectionDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        onConfirm: (examIds, thresholds, global, level) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssessmentActionPlanScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
                initialExamIds: examIds,
                initialThresholds: thresholds,
                initialGlobalThreshold: global,
                initialClassLevel: level,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirm(String id) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Silme Onayı', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Text('Bu eylem planını silmek istediğinize emin misiniz?', style: TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal')),
          TextButton(
            onPressed: () async {
              await _service.deleteAssessmentActionPlan(id);
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStatusUpdateDialog(AssessmentActionPlan plan) {
    final notesController = TextEditingController(text: plan.realizationNotes);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                plan.isRealized ? 'Tamamlanan Eylem Planı (Pasif)' : 'Eylem Planı İzleme & Tamamlama',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                plan.isRealized
                    ? (plan.realizedDate != null
                        ? 'Gerçekleşme tarihi: ${DateFormat("dd.MM.yyyy HH:mm").format(plan.realizedDate!)} • İsterseniz tekrar Aktif listeye alabilirsiniz.'
                        : 'Bu plan gerçekleşti olarak işaretlenip Pasif listeye taşınmıştır.')
                    : 'Gerçekleşti olarak işaretlenen eylem planları otomatik olarak Pasif sekmesine taşınır.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notesController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'İzleme / gerçekleşme notları...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 20),
              if (!plan.isRealized)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _service.updateActionPlanRealization(
                            plan.id,
                            false,
                            notesController.text.trim(),
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('İzleme notu kaydedildi.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Notu Kaydet'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigo.shade800,
                          side: BorderSide(color: Colors.indigo.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _service.updateActionPlanRealization(
                            plan.id,
                            true,
                            notesController.text.trim(),
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Eylem planı gerçekleşti olarak işaretlendi ve Pasif listesine taşındı.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text(
                          'Gerçekleşti İşaretle (Pasife Al)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _service.updateActionPlanRealization(
                            plan.id,
                            false,
                            notesController.text.trim(),
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Eylem planı tekrar Aktif listesine alındı.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Tekrar Aktife Al'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange.shade800,
                          side: BorderSide(color: Colors.orange.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _service.updateActionPlanRealization(
                            plan.id,
                            true,
                            notesController.text.trim(),
                          );
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Notlar güncellendi.')),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'Notu Güncelle',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  Widget _buildEmptyState({required bool isPassiveTab, required int otherTabCount}) {
    final title = isPassiveTab
        ? 'Pasif eylem planı bulunmuyor'
        : 'Aktif eylem planı bulunmuyor';
    final subtitle = isPassiveTab
        ? 'Gerçekleşti olarak işaretlenen eylem planları burada arşivlenir.'
        : (otherTabCount > 0
            ? 'Tamamlanan $otherTabCount plan Pasif sekmesinde yer alıyor. Sağ alttan yeni plan oluşturabilirsiniz.'
            : 'Henüz eylem planı oluşturulmamış. Sağ alttaki butondan yeni plan başlatabilirsiniz.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPassiveTab ? Icons.inventory_2_outlined : Icons.assignment_turned_in_outlined,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
