import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../models/school/homework_model.dart';

class HomeworkDetailScreen extends StatefulWidget {
  final Homework homework;

  const HomeworkDetailScreen({super.key, required this.homework});

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen> {
  late Homework _homework;
  List<Map<String, dynamic>> _studentDetails = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _homework = widget.homework;
    _fetchStudentDetails();
  }

  Future<void> _fetchStudentDetails() async {
    if (_homework.targetStudentIds.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      List<Map<String, dynamic>> allStudents = [];

      final chunks = [];
      for (var i = 0; i < _homework.targetStudentIds.length; i += 10) {
        chunks.add(
          _homework.targetStudentIds.sublist(
            i,
            i + 10 > _homework.targetStudentIds.length
                ? _homework.targetStudentIds.length
                : i + 10,
          ),
        );
      }

      for (var chunk in chunks) {
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        allStudents.addAll(
          snap.docs.map((d) {
            final data = d.data();
            data['id'] = d.id;
            return data;
          }),
        );
      }

      allStudents.sort(
        (a, b) => (a['fullName'] ?? a['name'] ?? '').toString().compareTo(
          b['fullName'] ?? b['name'] ?? '',
        ),
      );

      if (mounted) {
        setState(() {
          _studentDetails = allStudents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching student details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('homeworks')
          .doc(_homework.id)
          .update({'studentStatuses': _homework.studentStatuses});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Değişiklikler kaydedildi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _updateStatus(String studentId, int status) {
    setState(() {
      final newStatuses = Map<String, int>.from(_homework.studentStatuses);

      // Toggle logic: If clicking the same status, revert to pending (0)
      if (newStatuses[studentId] == status) {
        newStatuses[studentId] = 0;
      } else {
        newStatuses[studentId] = status;
      }

      _homework = Homework(
        id: _homework.id,
        institutionId: _homework.institutionId,
        classId: _homework.classId,
        lessonId: _homework.lessonId,
        teacherId: _homework.teacherId,
        title: _homework.title,
        content: _homework.content,
        createdAt: _homework.createdAt,
        assignedDate: _homework.assignedDate,
        dueDate: _homework.dueDate,
        attachments: _homework.attachments,
        targetStudentIds: _homework.targetStudentIds,
        studentStatuses: newStatuses,
      );
    });
  }

  Widget _buildStatusOption(
    String studentId,
    int currentStatus,
    int value,
    IconData icon,
    Color color,
    String tooltip,
  ) {
    final isSelected = currentStatus == value;
    return InkWell(
      onTap: () => _updateStatus(studentId, value),
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected ? Colors.white : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  void _bulkUpdate(int status) {
    setState(() {
      final newStatuses = Map<String, int>.from(_homework.studentStatuses);
      for (var student in _studentDetails) {
        final uid = student['id'];
        if (uid != null) {
          newStatuses[uid] = status;
        }
      }

      _homework = Homework(
        id: _homework.id,
        institutionId: _homework.institutionId,
        classId: _homework.classId,
        lessonId: _homework.lessonId,
        teacherId: _homework.teacherId,
        title: _homework.title,
        content: _homework.content,
        createdAt: _homework.createdAt,
        assignedDate: _homework.assignedDate,
        dueDate: _homework.dueDate,
        attachments: _homework.attachments,
        targetStudentIds: _homework.targetStudentIds,
        studentStatuses: newStatuses,
      );
    });
  }

  Widget _buildBulkAction(int status, IconData icon, Color color) {
    return InkWell(
      onTap: () => _bulkUpdate(status),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Ödev Kontrolü',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton.icon(
            onPressed: _saveChanges,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('KAYDET'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _homework.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _homework.content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Veriliş: ${DateFormat('dd.MM.yyyy').format(_homework.assignedDate)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _homework.dueDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            _homework = Homework(
                              id: _homework.id,
                              institutionId: _homework.institutionId,
                              classId: _homework.classId,
                              lessonId: _homework.lessonId,
                              teacherId: _homework.teacherId,
                              title: _homework.title,
                              content: _homework.content,
                              createdAt: _homework.createdAt,
                              assignedDate: _homework.assignedDate,
                              dueDate: picked, // Updated
                              attachments: _homework.attachments,
                              targetStudentIds: _homework.targetStudentIds,
                              studentStatuses: _homework.studentStatuses,
                            );
                          });
                          // Trigger save immediately for date change or let user click save?
                          // User requested "update when clicked", usually implies edit.
                          // For safety, let's call save or just let the main save button handle it.
                          // The main save button handles all state changes.
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 14,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Kontrol: ${DateFormat('dd.MM.yyyy').format(_homework.dueDate)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.edit,
                              size: 12,
                              color: Colors.red.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_homework.attachments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _homework.attachments
                        .map(
                          (a) => ActionChip(
                            elevation: 0,
                            backgroundColor: Colors.blue.shade50,
                            side: BorderSide.none,
                            avatar: CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Icon(
                                a.type == 'link'
                                    ? Icons.link
                                    : Icons.attach_file,
                                size: 14,
                                color: Colors.blue,
                              ),
                            ),
                            label: Text(
                              a.title,
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: () async {
                              if (await canLaunchUrlString(a.url)) {
                                launchUrlString(a.url);
                              } else {
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Link açılamadı.'),
                                    ),
                                  );
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),

          // List Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ÖĞRENCİ LİSTESİ (${_studentDetails.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),
                // Bulk Actions
                if (!_isLoading && _studentDetails.isNotEmpty)
                  Row(
                    children: [
                      Text(
                        'TÜMÜNE UYGULA:',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildBulkAction(1, Icons.check, Colors.green),
                      const SizedBox(width: 4),
                      _buildBulkAction(3, Icons.remove, Colors.orange),
                      const SizedBox(width: 4),
                      _buildBulkAction(2, Icons.close, Colors.red),
                      const SizedBox(width: 4),
                      _buildBulkAction(
                        4,
                        Icons.no_backpack_outlined,
                        Colors.purple,
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Student List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _studentDetails.length,
                    itemBuilder: (context, index) {
                      final s = _studentDetails[index];
                      final uid = s['id'];
                      final name = s['fullName'] ?? s['name'] ?? 'İsimsiz';
                      final status = _homework.studentStatuses[uid] ?? 0;

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatusOption(
                                uid,
                                status,
                                1,
                                Icons.check,
                                Colors.green,
                                'Yaptı',
                              ),
                              const SizedBox(width: 8),
                              _buildStatusOption(
                                uid,
                                status,
                                3,
                                Icons.remove,
                                Colors.orange,
                                'Eksik',
                              ),
                              const SizedBox(width: 8),
                              _buildStatusOption(
                                uid,
                                status,
                                2,
                                Icons.close,
                                Colors.red,
                                'Yapmadı',
                              ),
                              const SizedBox(width: 8),
                              _buildStatusOption(
                                uid,
                                status,
                                4,
                                Icons.no_backpack_outlined,
                                Colors.purple,
                                'Getirmedi',
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
    );
  }
}
