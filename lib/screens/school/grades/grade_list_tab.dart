import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'exam_creation_dialog.dart';
import 'grade_entry_dialog.dart';

class GradeListTab extends StatefulWidget {
  final String institutionId;
  final String classId;
  final String lessonId;
  final String lessonName;

  const GradeListTab({
    super.key,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
  });

  @override
  State<GradeListTab> createState() => _GradeListTabState();
}

class _GradeListTabState extends State<GradeListTab> {
  int _studentCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchStudentCount();
  }

  Future<void> _fetchStudentCount() async {
    final snap = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('classId', isEqualTo: widget.classId)
        .count()
        .get();
    if (mounted) {
      setState(() {
        _studentCount = snap.count ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('class_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .where('lessonId', isEqualTo: widget.lessonId)
          // Removed server-side ordering to avoid index issues. Sorting client-side below.
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                'Bir hata oluştu:\n${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.grading_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'Henüz sınav tanımlanmamış',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showCreateDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Sınav Oluştur'),
                ),
              ],
            ),
          );
        }

        // Client-side sorting
        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final dA = (a.data() as Map<String, dynamic>);
          final dB = (b.data() as Map<String, dynamic>);
          final tA = dA['date'] as Timestamp?;
          final tB = dB['date'] as Timestamp?;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA); // Descending
        });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showCreateDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Sınav Oluştur'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final date = (data['date'] as Timestamp?)?.toDate();
                  final grades = data['grades'] as Map<String, dynamic>? ?? {};
                  final gradedCount = grades.length;
                  final dateStr = date != null
                      ? DateFormat('dd MMM yyyy', 'tr_TR').format(date)
                      : 'Tarihsiz';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          date != null ? DateFormat('dd').format(date) : '-',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      title: Text(
                        data['examName'] ?? 'Sınav',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('$dateStr'),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$gradedCount / $_studentCount not girildi',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showCreateDialog(examToEdit: data, docId: doc.id);
                          } else if (value == 'delete') {
                            _deleteExam(doc.id);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('Düzenle'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Sil'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _openGradeEntry(doc.id, data),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog({
    Map<String, dynamic>? examToEdit,
    String? docId,
  }) async {
    // If editing, merge ID into map
    Map<String, dynamic>? editData = examToEdit;
    if (editData != null && docId != null) {
      editData['id'] = docId;
    }

    await showDialog(
      context: context,
      builder: (_) => ExamCreationDialog(
        institutionId: widget.institutionId,
        classId: widget.classId,
        lessonId: widget.lessonId,
        lessonName: widget.lessonName,
        examToEdit: editData,
      ),
    );
  }

  Future<void> _deleteExam(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sınavı Sil'),
        content: const Text(
          'Bu sınavı ve girilen notları silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('class_exams')
            .doc(docId)
            .delete();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sınav silindi.')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _openGradeEntry(String examId, Map<String, dynamic> data) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GradeEntryDialog(
          institutionId: widget.institutionId,
          classId: widget.classId,
          lessonId: widget.lessonId,
          lessonName: widget.lessonName,
          examId: examId,
          initialData: data,
        ),
      ),
    );
  }
}
