import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// dart:html kaldırıldı – mobil uyumlu navigasyon kullanılıyor
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
import 'external_exam_attendance_stats_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../screens/public/external_exam_attendance_screen.dart';

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
  late Stream<ExternalExam> _examStream;

  static const _primaryColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _exam = widget.exam;
    _examStream = FirebaseFirestore.instance
        .collection('external_exams')
        .doc(widget.exam.id)
        .snapshots()
        .map((doc) => ExternalExam.fromMap(doc.data()!, doc.id));
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ExternalExam>(
      stream: _examStream,
      initialData: widget.exam,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final exam = snapshot.data!;
        _exam = exam;
        
        final isMobile = MediaQuery.of(context).size.width < 768;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              exam.title,
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
                icon: const Icon(Icons.link_rounded),
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
                tooltip: 'Başvuru Linkini Kopyala',
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExternalExamFormScreen(
                        institutionId: widget.institutionId,
                        schoolTypeId: widget.schoolTypeId,
                        existingExam: exam,
                      ),
                    ),
                  );
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
                exam: exam,
                institutionId: widget.institutionId,
              ),

              // Tab 2: Salon Planı
              ExternalExamVenueScreen(
                exam: exam,
                institutionId: widget.institutionId,
              ),

              // Tab 3: Giriş Belgeleri
              _buildEntryCardsTab(exam),

              // Tab 4: İletişim
              ExternalExamMessagingScreen(
                exam: exam,
                institutionId: widget.institutionId,
              ),

              // Tab 5: Sınav Seviyeleri
              _buildExamLevelsTab(exam),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntryCardsTab(ExternalExam exam) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return StreamBuilder<List<ExternalExamRegistration>>(
      stream: _service.getRegistrations(_exam.id ?? ''),
      builder: (context, snapshot) {
        final regs = snapshot.data ?? [];
        final withSeats =
            regs.where((r) => r.assignedRoomId != null).toList();
        final scanned = regs.where((r) => r.isScanned == true).toList();
        final waiting = regs.length - withSeats.length;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards (4 boxes)
              LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: isMobile ? (constraints.maxWidth / 2) - 8 : (constraints.maxWidth / 4) - 12,
                        child: _buildStatTile('Toplam', '${regs.length}', Colors.blue, regs),
                      ),
                      SizedBox(
                        width: isMobile ? (constraints.maxWidth / 2) - 8 : (constraints.maxWidth / 4) - 12,
                        child: _buildStatTile('Salon Atandı', '${withSeats.length}', Colors.green, withSeats),
                      ),
                      SizedBox(
                        width: isMobile ? (constraints.maxWidth / 2) - 8 : (constraints.maxWidth / 4) - 12,
                        child: _buildStatTile('Bekleyen', '$waiting', Colors.orange, regs.where((r) => r.assignedRoomId == null).toList()),
                      ),
                      SizedBox(
                        width: isMobile ? (constraints.maxWidth / 2) - 8 : (constraints.maxWidth / 4) - 12,
                        child: _buildStatTile('Yoklama Alınan', '${scanned.length}', Colors.purple, scanned),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // Action buttons
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
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
                  ElevatedButton.icon(
                    onPressed: () => _openQRScanner(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(
                      'QR Okut',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Yoklama Al – uygulama içi gezinme (mobil uyumlu)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExternalExamAttendanceScreen(
                            examId: exam.id ?? '',
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.fact_check_rounded),
                    label: Text(
                      'Yoklama Al',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Yoklama Linkini Kopyala
                  ElevatedButton.icon(
                    onPressed: () {
                      final String baseUrl = '${Uri.base.scheme}://${Uri.base.host}${Uri.base.hasPort ? ':${Uri.base.port}' : ''}';
                      final String yoklamaUrl = '$baseUrl/yoklama-al-${exam.id}';
                      Clipboard.setData(ClipboardData(text: yoklamaUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Yoklama linki panoya kopyalandı!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(
                      'Yoklama Linki Kopyala',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExternalExamAttendanceStatsScreen(
                          exam: _exam,
                          allRegistrations: regs,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.analytics_rounded),
                    label: Text(
                      'Yoklama Raporları',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
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

  Widget _buildExamLevelsTab(ExternalExam exam) {
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
          ...(exam.gradeLevels).map((grade) {
            final trialId = exam.trialExamIds[grade];
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
                        grade == 'Mezun' ? 'Mzn' : '$grade.',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                            fontSize: grade == 'Mezun' ? 12 : 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          grade == 'Mezun' ? 'Mezun Seviyesi' : '$grade. Sınıf',
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

  Widget _buildStatTile(String label, String value, Color color, List<ExternalExamRegistration> list) {
    return InkWell(
      onTap: () => _showStudentListDialog(label, list),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showStudentListDialog(String title, List<ExternalExamRegistration> list) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$title Listesi (${list.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: list.isEmpty
              ? const Center(child: Text('Kayıt bulunamadı.'))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (c, i) => const Divider(),
                  itemBuilder: (c, i) {
                    final r = list[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('${r.gradeLevel}. Sınıf • TC: ${r.displayTcNo}', style: GoogleFonts.inter(fontSize: 12)),
                      trailing: r.isScanned ? const Icon(Icons.check_circle, color: Colors.green, size: 20) : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _openQRScanner() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    onDetect: (capture) async {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final code = barcodes.first.rawValue;
                        if (code != null) {
                          Navigator.pop(ctx);
                          _processQR(code);
                        }
                      }
                    },
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text('QR Kodu Okutun', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _processQR(String code) async {
    final regs = await _service.getRegistrations(_exam.id ?? '').first;
    final match = regs.where((r) => r.id == code || r.studentTcNo == code).toList();
    if (match.isNotEmpty) {
      final reg = match.first;
      if (reg.isScanned) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${reg.fullName} zaten okutulmuş!'), backgroundColor: Colors.orange));
      } else {
        // 1) isScanned flag'i güncelle
        await _service.markAsScanned(reg.id!, true);

        // 2) Öğrenci bir salona atandıysa external_exam_attendance kaydına da işle
        if (reg.assignedRoomId != null && reg.id != null) {
          try {
            final attendSnap = await FirebaseFirestore.instance
                .collection('external_exam_attendance')
                .where('examId', isEqualTo: _exam.id)
                .where('roomId', isEqualTo: reg.assignedRoomId)
                .limit(1)
                .get();

            if (attendSnap.docs.isNotEmpty) {
              final doc = attendSnap.docs.first;
              final List<dynamic> attendances = List<dynamic>.from(doc.data()['attendances'] ?? []);
              // Kaydı bul ve attended = true yap
              bool found = false;
              for (int i = 0; i < attendances.length; i++) {
                if (attendances[i]['registrationId'] == reg.id) {
                  attendances[i] = Map<String, dynamic>.from(attendances[i])..["attended"] = true;
                  found = true;
                  break;
                }
              }
              if (!found) {
                // Listede yoksa ekle
                attendances.add({
                  'registrationId': reg.id,
                  'studentName': reg.fullName,
                  'studentTcNo': reg.studentTcNo,
                  'gradeLevel': reg.gradeLevel,
                  'seatNumber': reg.seatNumber,
                  'attended': true,
                });
              }
              final attendedCount = attendances.where((a) => a['attended'] == true).length;
              await doc.reference.update({
                'attendances': attendances,
                'attendedCount': attendedCount,
                'savedAt': FieldValue.serverTimestamp(),
              });
            }
          } catch (e) {
            debugPrint('Attendance güncelleme hatası: $e');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${reg.fullName} başarıyla okutuldu!'), backgroundColor: Colors.green));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt bulunamadı! Lütfen geçerli bir belge okutun.'), backgroundColor: Colors.red));
    }
  }
}
