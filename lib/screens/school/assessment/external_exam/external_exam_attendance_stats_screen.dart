import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';
import '../../../../services/external_exam_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class ExternalExamAttendanceStatsScreen extends StatefulWidget {
  final ExternalExam exam;
  final List<ExternalExamRegistration> allRegistrations;

  const ExternalExamAttendanceStatsScreen({
    Key? key,
    required this.exam,
    required this.allRegistrations,
  }) : super(key: key);

  @override
  State<ExternalExamAttendanceStatsScreen> createState() => _ExternalExamAttendanceStatsScreenState();
}

class _ExternalExamAttendanceStatsScreenState extends State<ExternalExamAttendanceStatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const _primaryColor = Color(0xFFF57C00);

  bool _isLoading = false;

  // Filtreler
  String _searchQuery = '';
  String? _selectedSchool;
  String? _selectedGrade;

  List<String> _schoolOptions = [];
  List<String> _gradeOptions = [];

  // PDF Fonts
  pw.Font? _cachedFont;
  pw.Font? _cachedFontBold;

  Map<String, bool> _attendanceOverrides = {};
  bool _isLoadingAttendance = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _attendanceSubscription;
  late Stream<List<ExternalExamRegistration>> _registrationsStream;
  final ExternalExamService _service = ExternalExamService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _registrationsStream = _service.getRegistrations(widget.exam.id ?? '');
    _extractFilterOptions();
    _preloadFonts();
    _listenToAttendanceOverrides();
  }

  void _listenToAttendanceOverrides() {
    _attendanceSubscription = FirebaseFirestore.instance
        .collection('external_exam_attendance')
        .where('examId', isEqualTo: widget.exam.id)
        .snapshots()
        .listen((snap) {
      final Map<String, bool> overrides = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final List<dynamic> attendances = data['attendances'] ?? [];
        for (final a in attendances) {
          final regId = a['registrationId'] as String?;
          final attended = a['attended'] as bool? ?? false;
          if (regId != null) {
            overrides[regId] = attended;
          }
        }
      }
      if (mounted) {
        setState(() {
          _attendanceOverrides = overrides;
          _isLoadingAttendance = false;
        });
      }
    }, onError: (e) {
      debugPrint('Yoklama izleme hatası: $e');
      if (mounted) {
        setState(() => _isLoadingAttendance = false);
      }
    });
  }

  bool _isStudentAttended(ExternalExamRegistration s) {
    if (_attendanceOverrides.containsKey(s.id)) {
      return _attendanceOverrides[s.id]!;
    }
    return s.isScanned;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  void _extractFilterOptions() {
    final schools = widget.allRegistrations.map((r) => r.currentSchool).where((s) => s.isNotEmpty).toSet().toList();
    schools.sort();
    final grades = widget.allRegistrations.map((r) => r.gradeLevel).where((g) => g.isNotEmpty).toSet().toList();
    grades.sort();

    setState(() {
      _schoolOptions = schools;
      _gradeOptions = grades;
    });
  }

  Future<void> _preloadFonts() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _cachedFont = pw.Font.ttf(fontData);
      final fontBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      _cachedFontBold = pw.Font.ttf(fontBoldData);
    } catch (e) {
      debugPrint('Local font load failed: $e');
    }
  }

  Future<pw.Font> _getFont() async => _cachedFont ?? pw.Font.helvetica();
  Future<pw.Font> _getFontBold() async => _cachedFontBold ?? pw.Font.helveticaBold();

  // Reset Logic
  Future<void> _resetAllAttendance() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Yoklamaları Sıfırla', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text('Bu sınava ait alınmış tüm yoklama verileri silinecektir. Öğrencilerin yoklama durumları "Katılmadı" olarak sıfırlanacaktır. Bu işlem geri alınamaz.\n\nEmin misiniz?', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Tümünü Sıfırla'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Delete all attendance docs for this exam
      final attendSnap = await FirebaseFirestore.instance
          .collection('external_exam_attendance')
          .where('examId', isEqualTo: widget.exam.id)
          .get();
      
      for (var doc in attendSnap.docs) {
        batch.delete(doc.reference);
      }

      // 2. Set isScanned = false for all registrations of this exam where isScanned == true
      final regSnap = await FirebaseFirestore.instance
          .collection('external_exam_registrations')
          .where('examId', isEqualTo: widget.exam.id)
          .where('isScanned', isEqualTo: true)
          .get();

      for (var doc in regSnap.docs) {
        batch.update(doc.reference, {'isScanned': false});
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm yoklama verileri başarıyla sıfırlandı.'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Go back as the data is wiped
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PDF Generation Methods ---

  Future<void> _exportAbsentStudentsPdf(List<ExternalExamRegistration> absentList) async {
    setState(() => _isLoading = true);
    try {
      final doc = pw.Document();
      final font = await _getFont();
      final fontBold = await _getFontBold();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.orange500, width: 2))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(widget.exam.title.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.orange900)),
                pw.Text('GELMEYEN ÖĞRENCİLER', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.grey800)),
              ]
            ),
          ),
          build: (context) => [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(35), // No (increased from 25)
                1: const pw.FlexColumnWidth(3),   // Name
                2: const pw.FlexColumnWidth(1.5), // Grade
                3: const pw.FlexColumnWidth(4),   // School
                4: const pw.FlexColumnWidth(2.5), // Phone
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('No', fontBold, isHeader: true, horizontalPadding: 4),
                    _pdfCell('Öğrenci Adı Soyadı', fontBold, isHeader: true),
                    _pdfCell('Sınıf', fontBold, isHeader: true),
                    _pdfCell('Okul', fontBold, isHeader: true),
                    _pdfCell('Veli Telefon', fontBold, isHeader: true),
                  ],
                ),
                // Data rows
                ...List.generate(absentList.length, (index) {
                  final s = absentList[index];
                  return pw.TableRow(
                    children: [
                      _pdfCell('${index + 1}', font, horizontalPadding: 4),
                      _pdfCell('${s.studentName} ${s.studentSurname}', font),
                      _pdfCell(s.gradeLevel, font),
                      _pdfCell(s.currentSchool, font),
                      _pdfCell(s.parentPhone, font),
                    ],
                  );
                }),
              ],
            )
          ]
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'gelmeyenler_${widget.exam.id}.pdf',
      );
    } catch (e) {
      debugPrint('PDF Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  pw.Widget _pdfCell(String text, pw.Font font, {bool isHeader = false, double horizontalPadding = 6}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: isHeader ? 10 : 9, color: isHeader ? PdfColors.black : PdfColors.grey800),
      ),
    );
  }

  List<ExternalExamRegistration> _filteredAbsentStudents(List<ExternalExamRegistration> registrations) {
    return registrations.where((s) {
      if (_isStudentAttended(s)) return false; // Sadece gelmeyenler
      if (s.status == RegistrationStatus.cancelled) return false;
      if (_selectedGrade != null && s.gradeLevel != _selectedGrade) return false;
      if (_selectedSchool != null && s.currentSchool != _selectedSchool) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = '${s.studentName} ${s.studentSurname}'.toLowerCase();
        if (!name.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => '${a.studentName} ${a.studentSurname}'.compareTo('${b.studentName} ${b.studentSurname}'));
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExternalExamRegistration>>(
      stream: _registrationsStream,
      initialData: widget.allRegistrations,
      builder: (context, snapshot) {
        final registrations = snapshot.data ?? [];
        final activeRegs = registrations.where((r) => r.status != RegistrationStatus.cancelled).toList();
        final totalAbsent = activeRegs.where((r) => !_isStudentAttended(r)).length;

        return Stack(
          children: [
            Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              appBar: AppBar(
                backgroundColor: _primaryColor,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: Text('Yoklama Raporları', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                actions: [
                  TextButton.icon(
                    onPressed: _resetAllAttendance,
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                    label: Text('Yoklamaları Sıfırla', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(horizontal: 16)),
                  ),
                  const SizedBox(width: 8),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  tabs: [
                    const Tab(text: 'Genel Durum & Salonlar'),
                    Tab(text: 'Gelmeyen Öğrenciler ($totalAbsent)'),
                  ],
                ),
              ),
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralStatsTab(registrations),
                  _buildAbsentStudentsTab(registrations),
                ],
              ),
            ),
            if (_isLoading || _isLoadingAttendance)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator(color: _primaryColor)),
              )
          ],
        );
      },
    );
  }

  Widget _buildGeneralStatsTab(List<ExternalExamRegistration> registrations) {
    final activeRegs = registrations.where((r) => r.status != RegistrationStatus.cancelled).toList();
    final total = activeRegs.length;
    final attended = activeRegs.where((r) => _isStudentAttended(r)).length;
    final absent = total - attended;
    final percent = total > 0 ? (attended / total * 100).toStringAsFixed(1) : '0.0';

    // Group by room
    final Map<String, List<ExternalExamRegistration>> roomGroups = {};
    for (var r in activeRegs) {
      final roomName = r.assignedRoomName ?? 'Atanmamış';
      roomGroups.putIfAbsent(roomName, () => []).add(r);
    }
    
    final sortedRooms = roomGroups.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dashboard Cards
          Row(
            children: [
              Expanded(child: _buildStatCard('Toplam', '$total', Icons.people_rounded, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatCard('Katılan', '$attended', Icons.check_circle_rounded, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatCard('Katılmayan', '$absent', Icons.cancel_rounded, Colors.red)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatCard('Katılım Oranı', '%$percent', Icons.pie_chart_rounded, Colors.purple)),
            ],
          ),
          const SizedBox(height: 32),
          Text('Salon Bazlı Katılım Durumu', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900)),
          const SizedBox(height: 16),
          
          ...sortedRooms.map((roomName) {
            final studentsInRoom = roomGroups[roomName]!;
            final roomAttended = studentsInRoom.where((r) => _isStudentAttended(r)).length;
            final roomTotal = studentsInRoom.length;
            final roomAbsent = roomTotal - roomAttended;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: ExpansionTile(
                title: Text('Salon: $roomName', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                subtitle: Text('$roomTotal Öğrenci | Katılan: $roomAttended | Gelmeyen: $roomAbsent', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: studentsInRoom.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (ctx, idx) {
                      final s = studentsInRoom[idx];
                      final attendedStatus = _isStudentAttended(s);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: attendedStatus ? Colors.green.shade50 : Colors.red.shade50,
                          child: Icon(attendedStatus ? Icons.check_rounded : Icons.close_rounded, color: attendedStatus ? Colors.green : Colors.red, size: 20),
                        ),
                        title: Text('${s.studentName} ${s.studentSurname}', style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14)),
                        subtitle: Text('${s.gradeLevel} - ${s.currentSchool}', style: GoogleFonts.inter(fontSize: 12)),
                        trailing: Text(attendedStatus ? 'GELDİ' : 'GELMEDİ', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: attendedStatus ? Colors.green : Colors.red)),
                      );
                    },
                  )
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAbsentStudentsTab(List<ExternalExamRegistration> registrations) {
    final list = _filteredAbsentStudents(registrations);

    return Column(
      children: [
        // Count banner showing filtered count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gelmeyen Öğrenci Sayısı (Filtrelere Göre): ${list.length}',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        // Filters
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Öğrenci Ara...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _selectedSchool,
                  hint: const Text('Tüm Okullar'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tüm Okullar')),
                    ..._schoolOptions.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _selectedSchool = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _selectedGrade,
                  hint: const Text('Tüm Sınıflar'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tümü')),
                    ..._gradeOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                  ],
                  onChanged: (v) => setState(() => _selectedGrade = v),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: list.isEmpty ? null : () => _exportAbsentStudentsPdf(list),
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Çıktı Al'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Gelmeyen öğrenci bulunamadı.', style: GoogleFonts.inter(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (ctx, idx) {
                    final s = list[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade50,
                          child: Icon(Icons.person_off_rounded, color: Colors.red.shade400, size: 20),
                        ),
                        title: Text('${s.studentName} ${s.studentSurname}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                        subtitle: Text('${s.gradeLevel} Sınıfı • ${s.currentSchool} • Veli: ${s.parentFullName} (${s.parentPhone})', style: GoogleFonts.inter(fontSize: 13)),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              Text(value, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            ],
          )
        ],
      ),
    );
  }
}
