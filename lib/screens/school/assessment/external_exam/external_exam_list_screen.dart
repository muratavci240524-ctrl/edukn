import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../services/external_exam_service.dart';
import 'external_exam_form_screen.dart';
import 'external_exam_detail_screen.dart';

class ExternalExamListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ExternalExamListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ExternalExamListScreen> createState() => _ExternalExamListScreenState();
}

class _ExternalExamListScreenState extends State<ExternalExamListScreen> {
  final ExternalExamService _service = ExternalExamService();

  // Orange brand color
  static const _primaryColor = Color(0xFFF57C00);
  static const _primaryLight = Color(0xFFFF8F00);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Dış Katılımlı Sınavlar',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateForm(context),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Yeni Sınav',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<ExternalExam>>(
        stream: _service.getExternalExams(widget.institutionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _primaryColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'Veriler yüklenemedi.',
                    style: GoogleFonts.inter(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Hata Detayı: ${snapshot.error}',
                      style: GoogleFonts.inter(
                        color: Colors.red.shade600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          final exams = snapshot.data ?? [];

          if (exams.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 32,
              vertical: 24,
            ),
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) =>
                _buildExamCard(context, exams[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 40,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Henüz sınav oluşturulmadı',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'İlk dış katılımlı sınavınızı oluşturmak için "Yeni Sınav" butonuna tıklayın.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _openCreateForm(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Yeni Sınav Oluştur',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCard(BuildContext context, ExternalExam exam) {
    final sessionCount = exam.applicationSessions.length;
    final String gradeText;
    if (exam.gradeLevels.contains('Mezun')) {
      final gradesOnly = exam.gradeLevels.where((g) => g != 'Mezun').join(', ');
      gradeText = gradesOnly.isEmpty ? 'Mezun' : '$gradesOnly. Sınıflar & Mezun';
    } else {
      gradeText = '${exam.gradeLevels.join(', ')}. Sınıflar';
    }

    return InkWell(
      onTap: () => _openDetail(context, exam),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: exam.isActive
                      ? [const Color(0xFFFF8F00), const Color(0xFFF57C00)]
                      : [Colors.grey.shade400, Colors.grey.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      exam.examType == ExamType.bursluluk
                          ? Icons.emoji_events_rounded
                          : Icons.science_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          exam.examTypeName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: exam.isActive
                          ? Colors.white
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      exam.isActive ? 'Aktif' : 'Pasif',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: exam.isActive ? _primaryColor : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.school_rounded,
                        gradeText,
                        Colors.blue.shade50,
                        Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      _buildInfoChip(
                        Icons.calendar_today_rounded,
                        '$sessionCount Seans',
                        Colors.purple.shade50,
                        Colors.purple.shade700,
                      ),
                      if (exam.scholarshipEnabled) ...[
                        const SizedBox(width: 12),
                        _buildInfoChip(
                          Icons.workspace_premium_rounded,
                          'Burs Aktif',
                          Colors.amber.shade50,
                          Colors.amber.shade700,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showDeleteConfirm(context, exam),
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 16, color: Colors.red.shade400),
                        label: Text(
                          'Sil',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: Colors.red.shade400),
                        ),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          final String baseUrl = "${Uri.base.scheme}://${Uri.base.host}${Uri.base.hasPort ? ':${Uri.base.port}' : ''}";
                          final String regUrl = "$baseUrl/sinav-basvuru?examId=${exam.id}";
                          Clipboard.setData(ClipboardData(text: regUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Başvuru linki panoya kopyalandı!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: const Icon(Icons.link_rounded, size: 16, color: Colors.blue),
                        label: Text(
                          'Başvuru Linki',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: () => _openDetail(context, exam),
                        icon: const Icon(Icons.open_in_full_rounded,
                            size: 16, color: _primaryColor),
                        label: Text(
                          'Detay',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _primaryColor,
                              fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(
    IconData icon,
    String label,
    Color bgColor,
    Color fgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  void _openCreateForm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExternalExamFormScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, ExternalExam exam) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExternalExamDetailScreen(
          exam: exam,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirm(BuildContext context, ExternalExam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sınavı Sil',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '"${exam.title}" sınavını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && exam.id != null) {
      try {
        await _service.deleteExternalExam(exam.id!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sınav silindi.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme hatası: $e')),
          );
        }
      }
    }
  }
}
