import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/school/homework_model.dart';
import 'homework_detail_screen.dart';

class HomeworkListTab extends StatefulWidget {
  final String institutionId;
  final String classId;
  final String lessonId;

  const HomeworkListTab({
    super.key,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
  });

  @override
  State<HomeworkListTab> createState() => _HomeworkListTabState();
}

class _HomeworkListTabState extends State<HomeworkListTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('homeworks')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .where('lessonId', isEqualTo: widget.lessonId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('failed-precondition')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('İndeks oluşturuluyor, lütfen bekleyiniz...'),
              ),
            );
          }
          return Center(
            child: Text(
              'Hata: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        // In-memory sort
        docs.sort((a, b) {
          final tA =
              (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final tB =
              (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.assignment_outlined,
                    size: 48,
                    color: Colors.blue.shade300,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Henüz ödev verilmemiş',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sağ alttaki + butonuna basarak yeni ödev oluşturabilirsiniz.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            data['id'] = docs[index].id;
            // Handle missing assignedDate for backward compatibility if any
            if (data['assignedDate'] == null && data['createdAt'] != null) {
              data['assignedDate'] = data['createdAt'];
            }

            final hw = Homework.fromMap(data);
            final daysLeft = hw.dueDate.difference(DateTime.now()).inDays + 1;
            final isPastDue =
                daysLeft <
                0; // Check real logic, standard diff might be sensitive

            // Check grading status
            final total = hw.targetStudentIds.length;
            final graded = hw.studentStatuses.values.where((v) => v > 0).length;

            Color stripeColor;
            if (isPastDue && graded == 0) {
              stripeColor = Colors.red.shade400; // Late & untouched
            } else if (graded > 0 && graded < total) {
              stripeColor = Colors.orange.shade400; // In progress / incomplete
            } else if (graded == total && total > 0) {
              stripeColor = Colors.green.shade400; // fully graded
            } else {
              stripeColor = const Color(0xFF4F46E5); // Normal
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  // ...
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HomeworkDetailScreen(homework: hw),
                      ),
                    ).then((_) => setState(() {})); // Refresh on return
                  },
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Stripe
                        Container(
                          width: 6,
                          decoration: BoxDecoration(
                            color: stripeColor,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                            ),
                          ),
                        ),

                        // Content
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Veriliş: ${DateFormat('dd.MM.yyyy').format(hw.assignedDate)}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hw.attachments.isNotEmpty)
                                      Icon(
                                        Icons.attach_file,
                                        size: 16,
                                        color: Colors.grey.shade400,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  hw.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  hw.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Divider(height: 1),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.people_outline,
                                          size: 16,
                                          color: Color(0xFF4F46E5),
                                        ),
                                        const SizedBox(width: 6),
                                        Builder(
                                          builder: (_) {
                                            final total =
                                                hw.targetStudentIds.length;
                                            final graded = hw
                                                .studentStatuses
                                                .values
                                                .where((v) => v > 0)
                                                .length;
                                            return Text(
                                              '$graded/$total Öğrenci',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF4F46E5),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),

                                    Row(
                                      children: [
                                        Icon(
                                          isPastDue
                                              ? Icons.error_outline
                                              : Icons.event_available,
                                          size: 16,
                                          color: isPastDue
                                              ? Colors.red
                                              : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Son: ${DateFormat('dd.MM.yyyy').format(hw.dueDate)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isPastDue
                                                ? Colors.red
                                                : Colors.grey.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
}
