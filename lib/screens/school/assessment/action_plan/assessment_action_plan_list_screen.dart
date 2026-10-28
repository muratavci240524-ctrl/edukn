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
      if (plan.branchActionPlans.isNotEmpty) {
        for (var branchKey in plan.branchActionPlans.keys) {
          final branchName = branchKey.split('_').first;
          final match = RegExp(r'^(\d+)').firstMatch(branchName);
          if (match != null) {
            String raw = match.group(1)!;
            if (raw.length == 3) return raw[0];
            if (raw.length == 4) return raw.substring(0, 2);
            return raw;
          }
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
        
        // Collect resolved levels for filtering
        final Set<String> levels = allPlans
            .map((p) => _getResolvedLevel(p))
            .where((l) => l != 'GENEL')
            .toSet();
        final List<String> sortedLevels = ['Tümü', ...levels.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0))];

        final filteredPlans = allPlans.where((p) {
          if (_selectedClassFilter == 'Tümü') return true;
          return _getResolvedLevel(p) == _selectedClassFilter;
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
              ? FloatingActionButton.extended(
                  onPressed: () => _showSelectionModal(context),
                  backgroundColor: Colors.indigo.shade900,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Yeni Plan Oluştur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : null,
          body: allPlans.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildClassFilterBar(sortedLevels),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: filteredPlans.length,
                        itemBuilder: (context, index) => _buildPlanCard(filteredPlans[index]),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildClassFilterBar(List<String> sortedLevels) {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: sortedLevels.length,
        itemBuilder: (context, index) {
          final level = sortedLevels[index];
          final isSelected = _selectedClassFilter == level;
          final displayLabel = level == 'Tümü'
              ? 'Tüm Planlar'
              : (level.toLowerCase().contains('sınıf') ? level : '$level. Sınıf');

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => setState(() => _selectedClassFilter = level),
              borderRadius: BorderRadius.circular(25),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  gradient: isSelected 
                    ? LinearGradient(colors: [Colors.indigo.shade900, Colors.indigo.shade700])
                    : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : Colors.indigo.shade50,
                    width: 1.5,
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ] : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  displayLabel,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.indigo.shade900,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(AssessmentActionPlan plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        plan.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        _buildClassBadge(_getResolvedLevel(plan)),
                        const SizedBox(width: 8),
                        _buildStatusChip(plan.isRealized),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(DateFormat('dd.MM.yyyy HH:mm').format(plan.date), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    const SizedBox(width: 16),
                    Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    _buildCreatorText(plan),
                  ],
                ),
                const Divider(height: 32),
                Text(
                  'Kapsanan Sınavlar: ${plan.selectedExamNames.join(", ")}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showDeleteConfirm(plan.id),
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Sil', style: TextStyle(color: Colors.red)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showStatusUpdateDialog(plan),
                      icon: Icon(plan.isRealized ? Icons.check_circle : Icons.pending_actions, size: 18),
                      label: Text(plan.isRealized ? 'Gerçekleşti' : 'İzleme'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: plan.isRealized ? Colors.green.shade50 : Colors.orange.shade50,
                        foregroundColor: plan.isRealized ? Colors.green : Colors.orange,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _generateReport(plan),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Rapor Al'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade50,
                        foregroundColor: Colors.indigo.shade800,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

  Widget _buildCreatorText(AssessmentActionPlan plan) {
    if (plan.creatorName.isNotEmpty &&
        plan.creatorName != 'Kullanıcı' &&
        plan.creatorName != 'Sistem Yöneticisi' &&
        plan.creatorName != 'anon') {
      return Text(plan.creatorName,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12));
    }

    final cached = UserPermissionService.getCachedUserFullName(plan.createdBy);
    if (cached != null && cached != 'Sistem Yöneticisi') {
      return Text(cached,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12));
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
        return Text(name.isNotEmpty ? name : 'Yönetici',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12));
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRealized ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isRealized ? 'GERÇEKLEŞTİ' : 'BEKLEMEDE',
        style: TextStyle(color: isRealized ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Text(
        display,
        style: TextStyle(color: Colors.indigo.shade900, fontSize: 10, fontWeight: FontWeight.bold),
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
        title: const Text('Silme Onayı'),
        content: const Text('Bu eylem planını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('İptal')),
          TextButton(
            onPressed: () async {
              await _service.deleteAssessmentActionPlan(id);
              if (mounted) Navigator.pop(c);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
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
      builder: (context) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Eylem Planı İzleme', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: notesController,
                maxLines: 4,
                decoration: InputDecoration(hintText: 'Notlar...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await _service.updateActionPlanRealization(plan.id, true, notesController.text);
                    if (mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('Gerçekleşti İşaretle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => const Center(child: Text('Henüz eylem planı oluşturulmamış', style: TextStyle(color: Colors.grey)));
}
