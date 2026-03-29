import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'assessment_definitions_screen.dart';
import 'trial_exam_list_screen.dart';
import 'active_exam_list_screen.dart';
import 'assessment_reports_screen.dart';
import '../../../services/assessment_service.dart';
import '../../../models/assessment/trial_exam_model.dart';
import '../../../models/assessment/outcome_list_model.dart';

class AssessmentDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const AssessmentDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<AssessmentDashboardScreen> createState() => _AssessmentDashboardScreenState();
}

class _AssessmentDashboardScreenState extends State<AssessmentDashboardScreen> {
  final AssessmentService _assessmentService = AssessmentService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Ölçme Değerlendirme',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.indigo.shade900),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Removed (Title moved to AppBar)
                
                // Row 1: Tanımlar & Raporlar
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 2, child: _buildTanimlarCard()),
                            const SizedBox(width: 24),
                            Expanded(flex: 1, child: _buildRaporlarCard()),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildTanimlarCard(),
                          const SizedBox(height: 24),
                          _buildRaporlarCard(),
                        ],
                      );
                    }
                  },
                ),
                
                const SizedBox(height: 24),

                // Row 2: Denemeler & Sınavlar
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildSecondaryCard(
                              title: 'Denemeler (Sınav Tanımları)',
                              subtitle: 'Yeni deneme sınavları kurgulayın, soru dağılımlarını belirleyin ve uygulama takvimini yayınlayın.',
                              icon: Icons.edit_note_rounded,
                              iconColor: Colors.purple,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => TrialExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId))),
                              actions: ['Yeni Oluştur', 'Yayınla', 'Arşiv'],
                            )),
                            const SizedBox(width: 24),
                            Expanded(child: _buildSecondaryCard(
                              title: 'Sınavlar (Uygulama & Sonuç)',
                              subtitle: 'Yayınlanmış sınavların uygulama süreçlerini takip edin ve optik okuma sonuçlarını sisteme aktarın.',
                              icon: Icons.assignment_turned_in_rounded,
                              iconColor: Colors.teal,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => ActiveExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId))),
                              statusText: 'Şu an devam eden 4 sınav var',
                              isActive: true,
                            )),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildSecondaryCard(
                            title: 'Denemeler (Sınav Tanımları)',
                            subtitle: 'Yeni deneme sınavları kurgulayın...',
                            icon: Icons.edit_note_rounded,
                            iconColor: Colors.purple,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => TrialExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId))),
                            actions: ['Yeni Oluştur', 'Yayınla', 'Arşiv'],
                          ),
                          const SizedBox(height: 24),
                          _buildSecondaryCard(
                            title: 'Sınavlar (Uygulama & Sonuç)',
                            subtitle: 'Yayınlanmış sınavların uygulama süreçlerini takip edin...',
                            icon: Icons.assignment_turned_in_rounded,
                            iconColor: Colors.teal,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => ActiveExamListScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId))),
                            statusText: 'Şu an devam eden 4 sınav var',
                            isActive: true,
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTanimlarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), shape: BoxShape.circle),
            child: const Icon(Icons.library_books_rounded, color: Colors.indigo, size: 24),
          ),
          const SizedBox(height: 24),
          Text('Tanımlar', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
          const SizedBox(height: 8),
          Text(
            'Sınav türlerini yapılandırın, optik form şablonlarını yönetin\nve akademik kazanımları eşleştirin.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500, height: 1.5),
          ),
          const SizedBox(height: 32),
          
          StreamBuilder<int>(
            stream: _assessmentService.getExamTypes(widget.institutionId).map((list) => list.length),
            builder: (context, typeSnapshot) {
              return StreamBuilder<int>(
                stream: _assessmentService.getOpticalForms(widget.institutionId).map((list) => list.length),
                builder: (context, formSnapshot) {
                  return StreamBuilder<List<dynamic>>(
                    stream: _assessmentService.getOutcomeLists(widget.institutionId),
                    builder: (context, outcomeSnapshot) {
                      // Calculate total outcomes across all lists
                      int totalOutcomesCount = 0;
                      if (outcomeSnapshot.hasData && outcomeSnapshot.data != null) {
                        for (final list in outcomeSnapshot.data!) {
                          if (list is OutcomeList) {
                            totalOutcomesCount += list.outcomes.length;
                          }
                        }
                      }
                      
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _buildStatBox('TÜRLER', '${typeSnapshot.data ?? 0} Sınav Türü'),
                          _buildStatBox('FORMLAR', '${formSnapshot.data ?? 0} Aktif Optik'),
                          _buildStatBox('KAZANIM', _formatDataCount(totalOutcomesCount)),
                        ],
                      );
                    }
                  );
                }
              );
            }
          ),
          
          const SizedBox(height: 48),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => AssessmentDefinitionsScreen(institutionId: widget.institutionId))),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Yönetmeye Başla'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDataCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k Veri';
    }
    return '$count Veri';
  }

  Widget _buildStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
        ],
      ),
    );
  }

  Widget _buildRaporlarCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 24),
          Text('Raporlar', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text(
            'Sınav sonuçlarını, öğrenci gelişim grafiklerini ve kurumsal başarı metriklerini detaylıca inceleyin.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withOpacity(0.8), height: 1.5),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => AssessmentReportsScreen(institutionId: widget.institutionId, schoolTypeId: widget.schoolTypeId))),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.indigo.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              minimumSize: const Size(double.infinity, 54),
              elevation: 0,
            ),
            child: const Text('Raporları Aç', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    List<String>? actions,
    String? statusText,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500, height: 1.5)),
            const SizedBox(height: 32),
            if (actions != null)
              Wrap(
                spacing: 8,
                children: actions.map((a) => Chip(
                  label: Text(a, style: const TextStyle(fontSize: 12)),
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide.none,
                )).toList(),
              ),
            if (isActive)
              StreamBuilder<List<TrialExam>>(
                stream: _assessmentService.getTrialExams(widget.institutionId),
                builder: (context, snapshot) {
                  final activeCount = snapshot.data?.where((e) => e.isPublished).length ?? 0;
                  final launchedCount = snapshot.data?.where((e) => e.isLaunched).length ?? 0;
                  
                  return Row(
                    children: [
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
                         child: Text('$activeCount AKTİF', style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                       ),
                       const SizedBox(width: 12),
                       Text('Şu an devam eden $launchedCount sınav var', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  );
                }
              ),
          ],
        ),
      ),
    );
  }
}
