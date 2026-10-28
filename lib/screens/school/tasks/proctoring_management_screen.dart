import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'proctoring_session_screen.dart';

// ─── Model ──────────────────────────────────────────────────────────────────

class ProctoringExam {
  final String id;
  final String name;
  final DateTime examDate;
  final List<String> classIds;
  final List<String> classNames;
  final bool isShared;
  final DateTime? createdAt;

  const ProctoringExam({
    required this.id,
    required this.name,
    required this.examDate,
    required this.classIds,
    required this.classNames,
    required this.isShared,
    this.createdAt,
  });

  factory ProctoringExam.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProctoringExam(
      id: doc.id,
      name: d['name'] as String? ?? 'İsimsiz Sınav',
      examDate: (d['examDate'] as Timestamp).toDate(),
      classIds: List<String>.from(d['classIds'] as List? ?? []),
      classNames: List<String>.from(d['classNames'] as List? ?? []),
      isShared: d['isShared'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─── Ana Ekran ───────────────────────────────────────────────────────────────

class ProctoringManagementScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const ProctoringManagementScreen({
    super.key,
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
  });

  @override
  State<ProctoringManagementScreen> createState() =>
      _ProctoringManagementScreenState();
}

class _ProctoringManagementScreenState
    extends State<ProctoringManagementScreen> {
  final _df = DateFormat('dd MMMM yyyy', 'tr_TR');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: EduknAppBar(
        title: 'Gözetmenlik İşlemleri',
        subtitle: widget.schoolTypeName ?? 'Sınav Gözetmenlikleri',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateExamDialog,
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Sınav',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('proctoringExams')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId ?? '')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return _buildEmpty();

          final exams = docs
              .map((d) => ProctoringExam.fromDoc(d))
              .toList()
            ..sort((a, b) => b.examDate.compareTo(a.examDate));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _buildExamCard(exams[i]),
          );
        },
      ),
    );
  }

  // ─── Kart ────────────────────────────────────────────────────────────────

  Widget _buildExamCard(ProctoringExam exam) {
    final isUpcoming = exam.examDate.isAfter(DateTime.now());
    final isPast = !isUpcoming;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      shadowColor: const Color(0xFF7C3AED).withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openExam(exam),
        onLongPress: () => _showExamOptions(exam),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // İkon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isUpcoming
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isUpcoming
                      ? Icons.event_available_rounded
                      : Icons.event_note_rounded,
                  color: isUpcoming
                      ? const Color(0xFF7C3AED)
                      : Colors.grey.shade400,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              // İçerik
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Üst satır: İsim + Paylaşıldı badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            exam.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: isPast
                                  ? Colors.grey.shade500
                                  : const Color(0xFF1E293B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (exam.isShared) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Paylaşıldı',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Tarih
                    Text(
                      _df.format(exam.examDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: isUpcoming
                            ? const Color(0xFF7C3AED)
                            : Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (exam.classNames.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${exam.classNames.length} sınıf: ${exam.classNames.take(4).join(', ')}${exam.classNames.length > 4 ? '...' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Boş Durum ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined,
              size: 72, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          const Text(
            'Henüz sınav oluşturulmamış.',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Aşağıdaki "Yeni Sınav" butonu ile\ngözetmenlik çizelgesi oluşturun.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ─── Yeni Sınav Dialog ───────────────────────────────────────────────────

  Future<void> _showCreateExamDialog() async {
    final nameCtrl = TextEditingController();
    DateTime? selectedDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Yeni Gözetmenlik Sınavı',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Sınav Adı',
                  hintText: 'örn. 1. Dönem Sınavı',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon:
                      const Icon(Icons.drive_file_rename_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    locale: const Locale('tr'),
                  );
                  if (picked != null) setDialog(() => selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: selectedDate != null
                            ? const Color(0xFF7C3AED)
                            : Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: selectedDate != null
                            ? const Color(0xFF7C3AED)
                            : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        selectedDate != null
                            ? DateFormat('dd.MM.yyyy').format(selectedDate!)
                            : 'Sınav Tarihi Seç',
                        style: TextStyle(
                          color: selectedDate != null
                              ? const Color(0xFF1E293B)
                              : Colors.grey,
                          fontWeight: selectedDate != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Sınav adı ve tarih zorunludur.'),
                        backgroundColor: Colors.orange),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await _createExam(name, selectedDate!);
              },
              child: const Text('Oluştur',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createExam(String name, DateTime date) async {
    try {
      final ref = await FirebaseFirestore.instance
          .collection('proctoringExams')
          .add({
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId ?? '',
        'schoolTypeName': widget.schoolTypeName ?? '',
        'name': name,
        'examDate': Timestamp.fromDate(date),
        'classIds': [],
        'classNames': [],
        'isShared': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      // Yeni sınavı hemen aç
      _openExamById(ref.id, name, date);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _openExam(ProctoringExam exam) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProctoringSessionScreen(
          examId: exam.id,
          examName: exam.name,
          examDate: exam.examDate,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  void _openExamById(String id, String name, DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProctoringSessionScreen(
          examId: id,
          examName: name,
          examDate: date,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  // ─── Uzun Basma Seçenekleri ───────────────────────────────────────────────

  void _showExamOptions(ProctoringExam exam) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              exam.name,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              _df.format(exam.examDate),
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.red),
              title: const Text('Sınavı Sil',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text('Tüm gözetmen atamaları da silinir'),
              onTap: () async {
                Navigator.pop(context);
                await _deleteExam(exam);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExam(ProctoringExam exam) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sınavı Sil'),
        content: Text(
            '"${exam.name}" sınavını ve tüm gözetmen atamalarını silmek istiyor musunuz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Slotları sil
      final slots = await FirebaseFirestore.instance
          .collection('proctoringSlots')
          .where('examId', isEqualTo: exam.id)
          .get();
      for (final s in slots.docs) {
        await s.reference.delete();
      }
      // Sınavı sil
      await FirebaseFirestore.instance
          .collection('proctoringExams')
          .doc(exam.id)
          .delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Silme hatası: $e'),
            backgroundColor: Colors.red),
      );
    }
  }
}
