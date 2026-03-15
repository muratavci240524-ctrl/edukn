import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../models/todo_task.dart';
import 'create_task_screen.dart';

class ToDoListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ToDoListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ToDoListScreen> createState() => _ToDoListScreenState();
}

class _ToDoListScreenState extends State<ToDoListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

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
      backgroundColor: const Color(0xFFF7F8FC), // Soft gray-blue background
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(24),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
            title: const Text(
              'Görevlerim',
              style: TextStyle(
                color: Color(0xFF1E293B), // Slate 800
                fontWeight: FontWeight.w800,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
            iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
            bottom: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4F46E5), // Indigo 600
              unselectedLabelColor: const Color(0xFF94A3B8), // Slate 400
              indicatorSize: TabBarIndicatorSize.label,
              indicatorColor: const Color(0xFF4F46E5),
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Bana Atananlar'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.outbox_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Verdiğim Görevler'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateTaskScreen(
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          );
        },
        backgroundColor: const Color(0xFF4F46E5),
        elevation: 4,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_task, color: Colors.white),
        label: const Text(
          'Yeni Görev',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(isMyTask: true),
          _buildTaskList(isMyTask: false),
        ],
      ),
    );
  }

  Widget _buildTaskList({required bool isMyTask}) {
    // Construct Query
    Query query = FirebaseFirestore.instance
        .collection('tasks')
        .where('institutionId', isEqualTo: widget.institutionId);

    if (isMyTask) {
      query = query.where('assigneeIds', arrayContains: _currentUserId);
    } else {
      query = query.where('creatorId', isEqualTo: _currentUserId);
    }

    // Usually we want undone first, then archived/done.
    // Firestore limitation: cannot sort by multiple fields if filtering by arrayContains efficiently without index.
    // We sort client-side to avoid needing to create a composite index immediately.
    // query = query.orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Check for permission error specifically
          if (snapshot.error.toString().contains('permission-denied')) {
            return _buildErrorState(
              'Erişim izniniz yok. Lütfen yetkilinizle görüşün.',
            );
          }
          return _buildErrorState('Bir hata oluştu: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // Sort client-side
        docs.sort((a, b) {
          final aTime = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTime = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); // Descending
        });

        if (docs.isEmpty) {
          return _buildEmptyState(
            isMyTask
                ? 'Harika! Yapılacak işiniz kalmadı.'
                : 'Henüz kimseye görev vermediniz.',
            isMyTask ? Icons.task_alt : Icons.assignment_ind_outlined,
          );
        }

        // Processing Lists
        final List<ToDoTask> pendingTasks = [];
        final List<ToDoTask> completedTasks = [];

        for (var doc in docs) {
          final task = ToDoTask.fromFirestore(doc);
          final isCompleted = task.completedBy.contains(_currentUserId);

          if (isMyTask && isCompleted) {
            completedTasks.add(task);
          } else if (!isMyTask &&
              task.completedBy.length == task.assigneeIds.length &&
              task.assigneeIds.isNotEmpty) {
            completedTasks.add(task);
          } else {
            pendingTasks.add(task);
          }
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            120,
            16,
            80,
          ), // Top padding accounting for AppBar
          children: [
            if (pendingTasks.isNotEmpty) ...[
              _buildSectionTitle(
                'Bekleyenler (${pendingTasks.length})',
                const Color(0xFF334155),
              ),
              ...pendingTasks.map(
                (t) => _buildModernTaskCard(t, isMyTask: isMyTask),
              ),
            ],

            if (completedTasks.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionTitle(
                'Tamamlananlar (${completedTasks.length})',
                const Color(0xFF94A3B8),
              ),
              ...completedTasks.map(
                (t) => _buildModernTaskCard(t, isMyTask: isMyTask),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildModernTaskCard(ToDoTask task, {required bool isMyTask}) {
    final bool isCompletedByMe = task.completedBy.contains(_currentUserId);
    final int completionCount = task.completedBy.length;
    final int totalAssignees = task.assigneeIds.length;
    final double progress = totalAssignees > 0
        ? completionCount / totalAssignees
        : 0.0;

    // Check if overdue
    bool isOverdue = false;
    if (task.deadline != null &&
        task.deadline!.isBefore(DateTime.now()) &&
        !isCompletedByMe) {
      if (!isMyTask && completionCount < totalAssignees) {
        isOverdue = true;
      } else if (isMyTask && !isCompletedByMe) {
        isOverdue = true;
      }
    }

    final cardColor =
        isCompletedByMe ||
            (!isMyTask &&
                completionCount == totalAssignees &&
                totalAssignees > 0)
        ? Colors.grey.shade50
        : Colors.white;

    final borderColor = isOverdue
        ? const Color(0xFFEF4444)
        : Colors.transparent; // Red-500

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue ? borderColor : Colors.white,
          width: isOverdue ? 1.5 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          // Detail view trigger could go here
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Role/Creator info + Action
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox or Icon
                  if (isMyTask)
                    InkWell(
                      onTap: () => _toggleTaskCompletion(task),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 24,
                        width: 24,
                        decoration: BoxDecoration(
                          color: isCompletedByMe
                              ? const Color(0xFF10B981)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCompletedByMe
                                ? const Color(0xFF10B981)
                                : const Color(0xFFCBD5E1),
                            width: 2,
                          ),
                        ),
                        child: isCompletedByMe
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    )
                  else
                    Container(
                      height: 24,
                      width: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        size: 14,
                        color: Color(0xFF4F46E5),
                      ),
                    ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            decoration: (isMyTask && isCompletedByMe)
                                ? TextDecoration.lineThrough
                                : null,
                            color: (isMyTask && isCompletedByMe)
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        if (task.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              task.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 12),

              // Footer: Date + Assignees
              Row(
                children: [
                  // Date Tag
                  if (task.deadline != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFF1F5F9), // Red-100 or Slate-100
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: isOverdue
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat(
                              'd MMM, HH:mm',
                              'tr_TR',
                            ).format(task.deadline!),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOverdue
                                  ? const Color(0xFFB91C1C)
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (task.recurrence != 'none') ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5FF), // Purple-50
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.repeat,
                            size: 12,
                            color: Color(0xFF9333EA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getRecurrenceLabel(task.recurrence),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF9333EA),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Assignee Avatars
                  SizedBox(
                    height: 24,
                    width: _calculateStackWidth(totalAssignees),
                    child: Stack(
                      children: [
                        ...List.generate(
                          totalAssignees > 3 ? 3 : totalAssignees,
                          (index) {
                            return Positioned(
                              left: index * 14.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF4F46E5,
                                  ).withOpacity(0.2),
                                  child: const Icon(
                                    Icons.person,
                                    size: 12,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (totalAssignees > 3)
                          Positioned(
                            left: 3 * 14.0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF94A3B8),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '+${totalAssignees - 3}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (totalAssignees > 0 && !isMyTask) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$completionCount/$totalAssignees',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),

              // Simple Progress Bar (Only if multiple people or I'm viewing as creator)
              if (!isMyTask || totalAssignees > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFF1F5F9),
                      color: progress == 1.0
                          ? const Color(0xFF10B981)
                          : const Color(0xFF4F46E5),
                      minHeight: 4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9), // Slate 100
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: const Color(0xFFCBD5E1),
            ), // Slate 300
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateStackWidth(int count) {
    if (count == 0) return 0;
    int visible = count > 3 ? 4 : count;
    return (visible - 1) * 14.0 + 24.0;
  }

  String _getRecurrenceLabel(String type) {
    switch (type) {
      case 'daily':
        return 'Günlük';
      case 'weekly':
        return 'Haftalık';
      case 'monthly':
        return 'Aylık';
      default:
        return type;
    }
  }

  Future<void> _toggleTaskCompletion(ToDoTask task) async {
    final docRef = FirebaseFirestore.instance.collection('tasks').doc(task.id);
    final isCompleted = task.completedBy.contains(_currentUserId);

    if (isCompleted) {
      await docRef.update({
        'completedBy': FieldValue.arrayRemove([_currentUserId]),
      });
    } else {
      await docRef.update({
        'completedBy': FieldValue.arrayUnion([_currentUserId]),
      });
    }
  }
}
