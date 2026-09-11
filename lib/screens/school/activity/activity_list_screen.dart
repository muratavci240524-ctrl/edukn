import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/activity_service.dart';
import '../../../../models/activity/activity_model.dart';
import 'activity_form_screen.dart';
import 'activity_detail_screen.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../../../services/term_service.dart';
import '../../../../services/user_permission_service.dart';

import 'activity_statistics_screen.dart'; // We will create this later

class ActivityListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const ActivityListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  }) : super(key: key);

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ActivityService _activityService = ActivityService();

  String? _activeTermId;
  String? _activeTermName;
  bool _isManager = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadContextData();
  }

  Future<void> _loadContextData() async {
    final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
    String? termName;
    if (termId != null && termId.isNotEmpty) {
      try {
        final termDoc = await FirebaseFirestore.instance.collection('terms').doc(termId).get();
        if (termDoc.exists) {
          termName = (termDoc.data()?['name'] ?? termDoc.data()?['termName'])?.toString();
        }
      } catch (_) {}
    }

    final userData = await UserPermissionService.loadUserData();
    final role = (userData?['role'] as String?)?.toLowerCase() ?? '';
    final title = (userData?['title'] as String?)?.toLowerCase() ?? '';
    final isManager = role.contains('admin') ||
        role.contains('mudur') ||
        role.contains('müdür') ||
        role.contains('kurucu') ||
        role.contains('rehber') ||
        title.contains('müdür') ||
        title.contains('rehber');

    if (mounted) {
      setState(() {
        _activeTermId = termId;
        _activeTermName = termName;
        _isManager = isManager;
      });
    }
  }

  Future<void> _confirmDelete(ActivityObservation activity) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Gözlem/Etkinlik Sil'),
        content: Text('"${activity.title}" kaydını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _activityService.deleteActivity(activity.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kayıt başarıyla silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(
        title: 'Gözlem ve Etkinlik İşlemleri',
        subtitle: widget.schoolTypeName + (_activeTermName != null ? ' • $_activeTermName' : ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'İstatistikler',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ActivityStatisticsScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: 'Gözlemler'),
            Tab(text: 'Etkinlikler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActivityList('observation'),
          _buildActivityList('activity'),
        ],
      ),
      floatingActionButton: UserPermissionService.canEditTeacherModule('rehberlik_islemleri', subModuleKey: 'gozlem_etkinlik_yeni_form')
          ? FloatingActionButton.extended(
              onPressed: () {
                // Pass the type based on current tab
                final type = _tabController.index == 0 ? 'observation' : 'activity';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ActivityFormScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      initialType: type,
                    ),
                  ),
                );
              },
              label: const Text('Yeni Ekle'),
              icon: const Icon(Icons.add),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _buildActivityList(String type) {
    return SafeStreamBuilder<List<ActivityObservation>>(
      stream: _activityService.getActivities(
        widget.institutionId,
        widget.schoolTypeId,
        type: type,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allActivities = snapshot.data ?? [];
        final activities = allActivities.where((a) {
          if (_activeTermId == null || _activeTermId!.isEmpty) return true;
          if (a.termId == null || a.termId!.isEmpty) return true;
          return a.termId == _activeTermId;
        }).toList();

        if (activities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type == 'observation'
                      ? Icons.visibility_off
                      : Icons.event_busy,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  type == 'observation'
                      ? 'Henüz gözlem kaydı yok'
                      : 'Henüz etkinlik kaydı yok',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            final color = type == 'observation' ? Colors.orange : Colors.blue;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ActivityDetailScreen(activity: activity),
                        ),
                      );
                    },
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          // Colored Strip
                          Container(width: 6, color: color),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          activity.title,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      if (activity.isEvaluationEnabled)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.green.shade200,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.assignment_turned_in,
                                                size: 12,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Değerlendirme',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${activity.date.day}.${activity.date.month}.${activity.date.year}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.grey.shade100,
                                        child: Icon(
                                          Icons.person,
                                          size: 14,
                                          color: color,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          activity.responsibleTeacherName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.group,
                                              size: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${activity.targetStudentIds.length}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_isManager && UserPermissionService.canEditTeacherModule('rehberlik_islemleri', subModuleKey: 'gozlem_etkinlik_yeni_form')) ...[
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ActivityFormScreen(
                                        institutionId: widget.institutionId,
                                        schoolTypeId: widget.schoolTypeId,
                                        initialType: activity.type,
                                        existingActivity: activity,
                                      ),
                                    ),
                                  );
                                } else if (value == 'delete') {
                                  _confirmDelete(activity);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('Düzenle'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Sil', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
