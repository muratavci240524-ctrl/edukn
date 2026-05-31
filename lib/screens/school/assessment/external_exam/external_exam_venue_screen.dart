import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../services/external_exam_service.dart';

class ExternalExamVenueScreen extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;

  const ExternalExamVenueScreen({
    Key? key,
    required this.exam,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ExternalExamVenueScreen> createState() =>
      _ExternalExamVenueScreenState();
}

class _ExternalExamVenueScreenState extends State<ExternalExamVenueScreen> {
  final ExternalExamService _service = ExternalExamService();
  bool _isAssigning = false;

  static const _primaryColor = Color(0xFFF57C00);

  @override
  Widget build(BuildContext context) {
    final venueConfig = widget.exam.venueConfig;
    final seatingModeName = venueConfig.seatingMode == SeatingMode.noSeating
        ? 'Salon Hazırlanmayacak'
        : venueConfig.seatingMode == SeatingMode.butterfly
            ? 'Kelebek Sistemi'
            : 'Rastgele Dağılım';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Seating mode info
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    venueConfig.seatingMode == SeatingMode.butterfly
                        ? Icons.scatter_plot_rounded
                        : venueConfig.seatingMode == SeatingMode.simpleRandom
                            ? Icons.shuffle_rounded
                            : Icons.no_accounts_rounded,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seatingModeName,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (venueConfig.seatingMode != SeatingMode.noSeating)
                        Text(
                          'Oturma planı oluşturulmak üzere yapılandırılmış.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (venueConfig.seatingMode == SeatingMode.noSeating)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu sınav için salon planı oluşturulmayacak. Sınav ayarlarından oturma düzenini değiştirebilirsiniz.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Sessions with assign button
            ...widget.exam.applicationSessions.map((session) => Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${session.sessionDate.day}.${session.sessionDate.month}.${session.sessionDate.year}',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: _primaryColor,
                                  fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            session.displayTime,
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.grey.shade500),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _isAssigning
                                ? null
                                : () => _assignSeats(session),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: _isAssigning
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.scatter_plot_rounded,
                                    size: 16),
                            label: Text(
                              'Dağıt',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: session.gradeLevels.map((g) {
                          final quota = session.gradeLevelQuotas[g] ?? 0;
                          return Chip(
                            label: Text('$g. Sınıf – $quota kota',
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.blue.shade50,
                            side: BorderSide.none,
                            labelStyle:
                                TextStyle(color: Colors.blue.shade700),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                )),

            const SizedBox(height: 16),

            // Classroom assignments
            if (venueConfig.classroomAssignments.isNotEmpty) ...[
              Text(
                'Derslik Atamaları',
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...venueConfig.classroomAssignments.map((assignment) =>
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${assignment.gradeLevel}. Sınıf – '
                          '${assignment.totalCapacity} kişilik kapasite',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: assignment.rooms.map((room) => Chip(
                            label: Text(
                              '${room.classroomName} (${room.effectiveCapacity})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: BorderSide.none,
                          )).toList(),
                        ),
                      ],
                    ),
                  )),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Henüz derslik ataması yapılmamış. Sınavı düzenleyerek salon planını tamamlayın.',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _assignSeats(ApplicationSession session) async {
    setState(() => _isAssigning = true);
    try {
      await _service.assignSeats(
        widget.exam.id ?? '',
        session.id,
        widget.exam.venueConfig.seatingMode,
        widget.exam.venueConfig.classroomAssignments,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oturma planı başarıyla oluşturuldu.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Oturma planı oluşturulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }
}
