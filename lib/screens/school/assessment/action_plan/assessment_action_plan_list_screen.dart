import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'assessment_action_plan_screen.dart';
import 'assessment_action_plan_selection_dialog.dart';
import 'assessment_action_plan_stats_screen.dart';
import '../../../../models/assessment/assessment_action_plan_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../widgets/edukn_logo.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    setState(() => _userRole = 'admin');
  }

  // Helper to get consistent class level across UI and filters
  String _getResolvedLevel(AssessmentActionPlan plan) {
    String level = plan.classLevel;
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
    return level;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AssessmentActionPlan>>(
      stream: _service.getAssessmentActionPlans(widget.institutionId, widget.schoolTypeId),
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
          appBar: AppBar(
            title: const Text('Eylem Planları Geçmişi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            backgroundColor: Colors.indigo.shade900,
            leading: const BackButton(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
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
          final displayLabel = level == 'Tümü' ? 'Tüm Planlar' : '$level. Sınıf';

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
                      color: Colors.indigo.withOpacity(0.3),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
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
                    Text(plan.creatorName, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showDeleteConfirm(plan.id),
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      label: const Text('Sil', style: TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(width: 12),
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
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isRealized) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isRealized ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isRealized ? 'GERÇEKLEŞTİ' : 'BEKLEMEDE',
        style: TextStyle(color: isRealized ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildClassBadge(String level) {
    String display = level == 'GENEL' ? 'GENEL' : '$level. SINIF';
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
              Navigator.pop(c);
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
                    Navigator.pop(context);
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
