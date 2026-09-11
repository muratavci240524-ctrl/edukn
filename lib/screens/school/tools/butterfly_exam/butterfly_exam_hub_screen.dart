import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../services/butterfly_pdf_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'butterfly_exam_wizard_screen.dart';
import 'butterfly_exam_detail_screen.dart';

/// Kelebek Sınav Dağıtıcı Ana Merkezi
class ButterflyExamHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const ButterflyExamHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<ButterflyExamHubScreen> createState() => _ButterflyExamHubScreenState();
}

class _ButterflyExamHubScreenState extends State<ButterflyExamHubScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Kelebek Sınav Dağıtıcı',
        subtitle: '${widget.schoolTypeName} • Çapraz Dağıtım & PDF Jeneratörü',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
        actions: [
          IconButton(
            tooltip: 'Yeni Sınav Oluştur',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5), size: 24),
            onPressed: _navigateToCreateWizard,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst Bilgi ve Arama Çubuğu
            _buildSearchAndInfoBar(isMobile),

            // Sınav Listesi
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('butterfly_exams')
                    .where('institutionId', isEqualTo: widget.institutionId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final errStr = snapshot.error.toString();
                    if (errStr.contains('permission-denied')) {
                      // Fallback stream from seating_plans
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('seating_plans')
                            .where('institutionId', isEqualTo: widget.institutionId)
                            .where('type', isEqualTo: 'butterfly_exam')
                            .snapshots(),
                        builder: (ctx2, snap2) {
                          if (snap2.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
                          }
                          final docs2 = snap2.data?.docs ?? [];
                          final exams2 = docs2
                              .map((d) => ExamDistribution.fromMap(d.data() as Map<String, dynamic>, d.id))
                              .toList();
                          exams2.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                          return _buildExamsListView(exams2, isMobile);
                        },
                      );
                    }
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final exams = docs
                      .map((d) => ExamDistribution.fromMap(d.data() as Map<String, dynamic>, d.id))
                      .toList();

                  // Tarihe göre yeniden eskiye sırala
                  exams.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                  return _buildExamsListView(exams, isMobile);
                },
              ),
            ),
          ],
        ),
      ),
      // Yeni Sınav Başlat Butonu
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _navigateToCreateWizard,
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'YENİ KELEBEK SINAV DAĞITIMI BAŞLAT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.4),
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ARAMA VE BİLGİ ŞERİDİ
  // ===========================================================================
  Widget _buildSearchAndInfoBar(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Arama Girişi
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Sınav adı, ders veya şube ara...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SINAV LİSTESİ GÖRÜNÜMÜ
  // ===========================================================================
  Widget _buildExamsListView(List<ExamDistribution> exams, bool isMobile) {
    final filteredExams = exams.where((e) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return e.title.toLowerCase().contains(query) ||
          e.lessonName.toLowerCase().contains(query) ||
          e.selectedClassNames.any((c) => c.toLowerCase().contains(query));
    }).toList();

    if (filteredExams.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredExams.length,
      itemBuilder: (context, index) {
        final exam = filteredExams[index];
        return _buildExamCard(exam, isMobile);
      },
    );
  }

  // ===========================================================================
  // TEKİL SINAV KARTI
  // ===========================================================================
  Widget _buildExamCard(ExamDistribution exam, bool isMobile) {
    final dateStr = DateFormat('dd.MM.yyyy').format(exam.examDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(exam),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Satır: Sınav Adı & Tarih
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.view_module_rounded, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              exam.lessonName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: const Color(0xFF4F46E5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                            const SizedBox(width: 6),
                            Text(
                              '$dateStr (${exam.examTime})',
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Menü Butonu (Sil / Düzenle)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                    onSelected: (val) {
                      if (val == 'view') _navigateToDetail(exam);
                      if (val == 'delete') _confirmDeleteExam(exam);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF4F46E5)),
                            SizedBox(width: 8),
                            Text('Detay ve Krokiyi Aç'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Sınav Oturumunu Sil', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Şubeler Rozetleri
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: exam.selectedClassNames.map((cName) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      cName,
                      style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // İstatistik Barı: Salon Sayısı & Oturan Öğrenci
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.meeting_room_rounded, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 5),
                        Text(
                          '${exam.rooms.length} Salon',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 5),
                        Text(
                          '${exam.seatedStudents} / ${exam.totalStudents} Yerleşen',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: exam.seatedStudents == exam.totalStudents
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Hızlı PDF Çıktı Butonları
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printAllGateLists(exam),
                      icon: const Icon(Icons.door_front_door_outlined, size: 16),
                      label: Text(
                        'Kapı Listesi PDF',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFFBAE6FD)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printAllSupervisorPlans(exam),
                      icon: const Icon(Icons.grid_on_rounded, size: 16),
                      label: Text(
                        'Gözetmen Krokisi PDF',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BOŞ DURUM
  // ===========================================================================
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.view_module_rounded, size: 56, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 18),
            Text(
              'Henüz Kelebek Sınavı Oluşturulmamış',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Farklı şube ve sınıf seviyelerindeki öğrencileri çapraz algoritmayla derslik oturma planlarına yerleştirmek için hemen yeni bir sınav dağıtımı başlatın.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _navigateToCreateWizard,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Yeni Sınav Dağıtımı Başlat', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // NAVİGASYON VE EYLEMLER
  // ===========================================================================
  void _navigateToCreateWizard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ButterflyExamWizardScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  void _navigateToDetail(ExamDistribution exam) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ButterflyExamDetailScreen(
          distribution: exam,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  Future<void> _printAllGateLists(ExamDistribution exam) async {
    try {
      final bytes = await ButterflyPdfService.generateAllGateListsPdf(distribution: exam);
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${exam.title}_Kapi_Listeleri.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printAllSupervisorPlans(ExamDistribution exam) async {
    try {
      final bytes = await ButterflyPdfService.generateAllSupervisorPlansPdf(distribution: exam);
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${exam.title}_Gozetmen_Krokileri.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF oluşturulurken hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteExam(ExamDistribution exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sınav Oturumunu Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          '"${exam.title}" sınav oturumunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && exam.id != null) {
      await FirebaseFirestore.instance.collection('butterfly_exams').doc(exam.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sınav oturumu başarıyla silindi.')),
        );
      }
    }
  }
}
