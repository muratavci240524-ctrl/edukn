import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'class_lesson_plan_entry_dialog.dart';

class ClassLessonPlanListTab extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;
  final String classId;
  final String lessonId;
  final String lessonName;

  const ClassLessonPlanListTab({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.periodId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
  }) : super(key: key);

  @override
  State<ClassLessonPlanListTab> createState() => _ClassLessonPlanListTabState();
}

class _ClassLessonPlanListTabState extends State<ClassLessonPlanListTab> {
  Future<void> _deletePlan(String planId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Planı Sil'),
        content: Text('Bu ders planını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('classLessonPlans')
          .doc(planId)
          .delete();
    }
  }

  void _editPlan(DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (_) => ClassLessonPlanEntryDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        periodId: widget.periodId,
        classId: widget.classId,
        lessonId: widget.lessonId,
        lessonName: widget.lessonName,
        existingPlanId: doc.id,
        existingPlanData: doc.data() as Map<String, dynamic>,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classLessonPlans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .where('lessonId', isEqualTo: widget.lessonId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Fallback if index error still persists (though removing orderBy usually fixes it)
          if (snapshot.error.toString().contains('failed-precondition')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'İndeks oluşturuluyor, lütfen bekleyiniz... (Birkaç dakika sürebilir)',
                ),
              ),
            );
          }
          return Center(child: Text('Hata oluştu: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_note_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                SizedBox(height: 16),
                Text(
                  'Henüz ders planı girilmemiş',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Yeni plan eklemek için + butonunu kullanabilirsin.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        // In-memory sort since we removed database sorting
        docs.sort((a, b) {
          final dateA =
              (a.data() as Map<String, dynamic>)['date'] as Timestamp?;
          final dateB =
              (b.data() as Map<String, dynamic>)['date'] as Timestamp?;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA); // Descending
        });

        return ListView.separated(
          padding: EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (context, index) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final date =
                (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
            final color = _getColorForIndex(index);

            final dayStr = DateFormat('dd').format(date);
            final monthYearStr = DateFormat('MM.yyyy').format(date);

            return InkWell(
              onTap: () => _editPlan(doc),
              borderRadius: BorderRadius.circular(16),
              child: Card(
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade100),
                ),
                margin: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Date Stripe
                        Container(
                          width: 80,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            border: Border(
                              right: BorderSide(color: color.withOpacity(0.2)),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayStr,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: color,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                monthYearStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Right Content
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['title'] ?? '',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 20,
                                        color: Colors.grey,
                                      ),
                                      onSelected: (value) {
                                        if (value == 'edit') _editPlan(doc);
                                        if (value == 'delete')
                                          _deletePlan(doc.id);
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                size: 18,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Düzenle'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete,
                                                size: 18,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Sil'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (data['content'] != null &&
                                    data['content'].toString().isNotEmpty) ...[
                                  SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.blue.shade300,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'KONU / İŞLENİŞ',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.blue.shade700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          data['content'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (data['outcome'] != null &&
                                    data['outcome'].toString().isNotEmpty) ...[
                                  SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: Colors.green.shade300,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'KAZANIM',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.green.shade700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          data['outcome'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade800,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                // Show attachment indicator if any
                                if (data['attachments'] != null &&
                                    (data['attachments'] as List)
                                        .isNotEmpty) ...[
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.attach_file,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        '${(data['attachments'] as List).length} Ek dosya',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
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

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}
