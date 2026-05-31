import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';
import '../../../../services/external_exam_service.dart';
import 'external_exam_form_screen.dart';
import 'external_exam_registrations_tab.dart';
import 'external_exam_venue_screen.dart';
import 'external_exam_messaging_screen.dart';
import 'external_exam_entry_card_screen.dart';

class ExternalExamDetailScreen extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;
  final String schoolTypeId;

  const ExternalExamDetailScreen({
    Key? key,
    required this.exam,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ExternalExamDetailScreen> createState() =>
      _ExternalExamDetailScreenState();
}

class _ExternalExamDetailScreenState extends State<ExternalExamDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExternalExamService _service = ExternalExamService();
  late ExternalExam _exam;

  static const _primaryColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _exam = widget.exam;
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _exam.title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExternalExamFormScreen(
                    institutionId: widget.institutionId,
                    schoolTypeId: widget.schoolTypeId,
                    existingExam: _exam,
                  ),
                ),
              );
              // Reload exam data after edit
              final updated =
                  await _service.getExternalExamById(_exam.id ?? '');
              if (updated != null && mounted) {
                setState(() => _exam = updated);
              }
            },
            tooltip: 'Düzenle',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.65),
          labelStyle: GoogleFonts.inter(
              fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle:
              GoogleFonts.inter(fontSize: 13),
          tabs: const [
            Tab(text: 'Başvurular'),
            Tab(text: 'Salon Planı'),
            Tab(text: 'Giriş Belgeleri'),
            Tab(text: 'İletişim'),
            Tab(text: 'Sınav Seviyeleri'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Başvurular
          ExternalExamRegistrationsTab(
            exam: _exam,
            institutionId: widget.institutionId,
          ),

          // Tab 2: Salon Planı
          ExternalExamVenueScreen(
            exam: _exam,
            institutionId: widget.institutionId,
          ),

          // Tab 3: Giriş Belgeleri
          _buildEntryCardsTab(),

          // Tab 4: İletişim
          ExternalExamMessagingScreen(
            exam: _exam,
            institutionId: widget.institutionId,
          ),

          // Tab 5: Sınav Seviyeleri
          _buildExamLevelsTab(),
        ],
      ),
    );
  }

  Widget _buildEntryCardsTab() {
    return StreamBuilder<List<ExternalExamRegistration>>(
      stream: _service.getRegistrations(_exam.id ?? ''),
      builder: (context, snapshot) {
        final regs = snapshot.data ?? [];
        final withSeats =
            regs.where((r) => r.assignedRoomId != null).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _buildStatTile('Toplam', '${regs.length}', Colors.blue),
                    const SizedBox(width: 16),
                    _buildStatTile(
                        'Salon Atandı', '${withSeats.length}', Colors.green),
                    const SizedBox(width: 16),
                    _buildStatTile(
                        'Bekleyen',
                        '${regs.length - withSeats.length}',
                        Colors.orange),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Bulk print button
              ElevatedButton.icon(
                onPressed: withSeats.isNotEmpty
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExternalExamEntryCardScreen(
                              exam: _exam,
                              registrations: withSeats,
                            ),
                          ),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.print_rounded),
                label: Text(
                  'Toplu Giriş Belgesi Bas (${withSeats.length})',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 16),

              if (_exam.venueConfig.seatingMode == SeatingMode.noSeating)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.blue.shade600, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bu sınav için salon planı oluşturulmayacak. Giriş belgelerinde salon/sıra bilgisi yer almaz.',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExamLevelsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sınav Seviyeleri',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Her sınıf seviyesi için TrialExam sınav tanımı seçin. Sınav sonuçları bu tanım üzerinden sisteme aktarılacaktır.',
            style: GoogleFonts.inter(
                fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ...(_exam.gradeLevels).map((grade) {
            final trialId = _exam.trialExamIds[grade];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$grade.',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                            fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$grade. Sınıf',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          trialId != null
                              ? 'TrialExam bağlı: $trialId'
                              : 'TrialExam henüz bağlanmadı',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: trialId != null
                                  ? Colors.green.shade600
                                  : Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    trialId != null
                        ? Icons.check_circle_rounded
                        : Icons.link_off_rounded,
                    color:
                        trialId != null ? Colors.green : Colors.grey.shade300,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  void _showPrintDialog(
      BuildContext context, List<ExternalExamRegistration> regs) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Giriş Belgesi',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          '${regs.length} öğrenci için giriş belgesi PDF oluşturulacak.\n\nBu özellik yakında hazır olacak.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}
