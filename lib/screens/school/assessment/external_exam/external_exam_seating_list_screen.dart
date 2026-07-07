import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';

class ExternalExamSeatingListScreen extends StatefulWidget {
  final ExternalExam exam;
  final List<ExternalExamRegistration> registrations;
  final String institutionId;

  const ExternalExamSeatingListScreen({
    Key? key,
    required this.exam,
    required this.registrations,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ExternalExamSeatingListScreen> createState() =>
      _ExternalExamSeatingListScreenState();
}

class _ExternalExamSeatingListScreenState
    extends State<ExternalExamSeatingListScreen> {
  static const _primaryColor = Color(0xFFF57C00);

  String _searchQuery = '';
  String? _selectedGrade;
  String? _selectedRoom;
  bool _isProcessing = false;

  // Real-time registrations stream to update list instantly on swaps
  late Stream<List<ExternalExamRegistration>> _regsStream;

  @override
  void initState() {
    super.initState();
    _regsStream = FirebaseFirestore.instance
        .collection('external_exam_registrations')
        .where('examId', isEqualTo: widget.exam.id ?? '')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => ExternalExamRegistration.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  List<ExternalExamRegistration> _filterList(List<ExternalExamRegistration> regs) {
    return regs.where((reg) {
      final matchesQuery = '${reg.studentName} ${reg.studentSurname}'
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          reg.studentTcNo.contains(_searchQuery);
      
      final matchesGrade = _selectedGrade == null || reg.gradeLevel == _selectedGrade;
      final matchesRoom = _selectedRoom == null || reg.assignedRoomName == _selectedRoom;

      return matchesQuery && matchesGrade && matchesRoom;
    }).toList()
      ..sort((a, b) {
        if (a.assignedRoomName != b.assignedRoomName) {
          return (a.assignedRoomName ?? '').compareTo(b.assignedRoomName ?? '');
        }
        return (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0);
      });
  }

  List<String> _getGrades(List<ExternalExamRegistration> regs) {
    final grades = regs.map((r) => r.gradeLevel).toSet().toList();
    grades.sort();
    return grades;
  }

  List<String> _getRooms(List<ExternalExamRegistration> regs) {
    final rooms = regs
        .map((r) => r.assignedRoomName)
        .whereType<String>()
        .toSet()
        .toList();
    rooms.sort();
    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return StreamBuilder<List<ExternalExamRegistration>>(
      stream: _regsStream,
      initialData: widget.registrations,
      builder: (context, snapshot) {
        final regs = snapshot.data ?? [];
        final filtered = _filterList(regs);
        final grades = _getGrades(regs);
        final rooms = _getRooms(regs);

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              'Öğrenci Dağıtım Listesi',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
            ),
            backgroundColor: _primaryColor,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _isProcessing
              ? const Center(child: CircularProgressIndicator(color: _primaryColor))
              : Column(
                  children: [
                    _buildFilterSection(grades, rooms),
                    _buildReportActionSection(regs),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, index) {
                                return _buildStudentCard(filtered[index], regs);
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFilterSection(List<String> grades, List<String> rooms) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Öğrenci Adı, Soyadı veya TC No ile ara...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                DropdownButton<String>(
                  value: _selectedGrade,
                  hint: Text('Tüm Sınıflar', style: GoogleFonts.inter(fontSize: 13)),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Tüm Sınıflar')),
                    ...grades.map((g) => DropdownMenuItem<String>(value: g, child: Text(g == 'Mezun' ? 'Mezun' : '$g. Sınıf'))),
                  ],
                  onChanged: (val) => setState(() => _selectedGrade = val),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedRoom,
                  hint: Text('Tüm Salonlar', style: GoogleFonts.inter(fontSize: 13)),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Tüm Salonlar')),
                    ...rooms.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))),
                  ],
                  onChanged: (val) => setState(() => _selectedRoom = val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportActionSection(List<ExternalExamRegistration> regs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _generateSeatingListPdf(regs, sortByRoom: true),
              icon: const Icon(Icons.print_rounded, size: 16, color: _primaryColor),
              label: Text('Salon Sıralı Yoklama Listesi', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryColor)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: _primaryColor)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _generateSeatingListPdf(regs, sortByRoom: false),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.blue),
              label: Text('İsim Sıralı Liste (A-Z)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(ExternalExamRegistration reg, List<ExternalExamRegistration> allRegs) {
    final gradeRooms = widget.exam.venueConfig.classroomAssignments
        .firstWhere((a) => a.gradeLevel == reg.gradeLevel, orElse: () => GradeClassroomAssignment(gradeLevel: reg.gradeLevel, rooms: []))
        .rooms;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                reg.gradeLevel == 'Mezun' ? 'Mzn' : '${reg.gradeLevel}.',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reg.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('TC: ${reg.studentTcNo}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
                if (reg.assignedRoomName != null)
                  Text(
                    '${reg.assignedRoomName} · Sıra: ${reg.seatNumber}',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                  )
                else
                  Text(
                    'Salon Atanmadı (Salonsuz)',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Swap room dropdown
          SizedBox(
            width: 160,
            child: DropdownButtonHideUnderline(
              child: DropdownButtonFormField<String?>(
                value: reg.assignedRoomId,
                isExpanded: true,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                hint: Text('Salon Seç', style: GoogleFonts.inter(fontSize: 12)),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Salondan Çıkar', style: GoogleFonts.inter(fontSize: 12, color: Colors.red)),
                  ),
                  ...gradeRooms.map(
                    (room) => DropdownMenuItem<String?>(
                      value: room.classroomId,
                      child: Text(room.classroomName, style: GoogleFonts.inter(fontSize: 12)),
                    ),
                  ),
                ],
                onChanged: (newRoomId) => _swapStudentRoom(reg, newRoomId, gradeRooms, allRegs),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _swapStudentRoom(
    ExternalExamRegistration reg,
    String? newRoomId,
    List<RoomSlot> gradeRooms,
    List<ExternalExamRegistration> allRegs,
  ) async {
    setState(() => _isProcessing = true);
    try {
      if (newRoomId == null) {
        // Option: Remove from room (unassign)
        await FirebaseFirestore.instance
            .collection('external_exam_registrations')
            .doc(reg.id)
            .update({
          'assignedRoomId': null,
          'assignedRoomName': null,
          'assignedRoomCode': null,
          'seatNumber': null,
        });
      } else {
        // Option: Move to a new room
        final targetRoom = gradeRooms.firstWhere((r) => r.classroomId == newRoomId);
        
        // Count how many students are currently in this new room
        final currentOccupancy = allRegs.where((r) =>
            r.assignedRoomId == newRoomId &&
            r.status != RegistrationStatus.cancelled).length;

        if (currentOccupancy >= targetRoom.effectiveCapacity) {
          // Warning: Capacity limit reached
          if (mounted) {
            bool proceed = await _showCapacityWarningDialog(targetRoom.classroomName);
            if (!proceed) {
              setState(() => _isProcessing = false);
              return;
            }
          }
        }

        final newSeat = currentOccupancy + 1;

        await FirebaseFirestore.instance
            .collection('external_exam_registrations')
            .doc(reg.id)
            .update({
          'assignedRoomId': targetRoom.classroomId,
          'assignedRoomName': targetRoom.classroomName,
          'assignedRoomCode': targetRoom.classroomCode,
          'seatNumber': newSeat,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Öğrenci salon ataması güncellendi.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Atama güncelleme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<bool> _showCapacityWarningDialog(String roomName) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kapasite Sınırı Aşıldı'),
            content: Text('"$roomName" salonunun kapasitesi dolmuş durumda. Yine de öğrenciyi bu salona taşımak istiyor musunuz?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, Devam Et')),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('Arama kriterlerine uygun öğrenci bulunamadı.', style: GoogleFonts.inter(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // PDF Generation Motor - Premium Design
  Future<void> _generateSeatingListPdf(List<ExternalExamRegistration> regs, {required bool sortByRoom}) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;
      font = await _loadRegularFont();
      fontBold = await _loadBoldFont();

      final slate800 = PdfColor.fromHex('#1e293b');
      final slate700 = PdfColor.fromHex('#334155');
      final slate50 = PdfColor.fromHex('#f8fafc');
      final slate900 = PdfColor.fromHex('#0f172a');
      final slate200 = PdfColor.fromHex('#e2e8f0');
      final slate100 = PdfColor.fromHex('#f1f5f9');

      if (sortByRoom) {
        // Group by Room
        final rooms = regs.map((r) => r.assignedRoomName).whereType<String>().toSet().toList();
        rooms.sort();

        if (rooms.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yazdırılacak salon/dağıtım verisi bulunamadı.'), backgroundColor: Colors.orange),
          );
          return;
        }

        for (final roomName in rooms) {
          final roomStudents = regs.where((r) => r.assignedRoomName == roomName).toList();
          roomStudents.sort((a, b) => (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0));

          final session = widget.exam.applicationSessions.firstWhere(
            (s) => roomStudents.isNotEmpty && s.id == roomStudents.first.sessionId,
            orElse: () => widget.exam.applicationSessions.isNotEmpty
                ? widget.exam.applicationSessions.first
                : ApplicationSession(id: '', sessionDate: DateTime.now(), startTime: '', endTime: '', gradeLevels: [], gradeLevelQuotas: {}),
          );

          doc.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              theme: pw.ThemeData.withFont(base: font, bold: fontBold),
              header: (context) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                padding: const pw.EdgeInsets.only(bottom: 6),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.orange500, width: 1)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      widget.exam.title.toUpperCase(),
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
                    ),
                    pw.Text(
                      'SALON YOKLAMA LİSTESİ · $roomName',
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: slate800),
                    ),
                  ],
                ),
              ),
              footer: (context) => pw.Container(
                margin: const pw.EdgeInsets.only(top: 12),
                padding: const pw.EdgeInsets.only(top: 6),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Salon Gözetmeni (Ad Soyad / İmza): ________________________________________',
                      style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Sayfa ${context.pageNumber}/${context.pagesCount}',
                      style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              build: (context) => [
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  margin: const pw.EdgeInsets.only(bottom: 14),
                  decoration: pw.BoxDecoration(
                    color: slate50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    border: pw.Border.all(color: slate100, width: 1),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            roomName,
                            style: pw.TextStyle(font: fontBold, fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            children: [
                              pw.Text('Seans: ', style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: slate700)),
                              pw.Text(session.displayTime, style: pw.TextStyle(font: font, fontSize: 9.5, color: slate700)),
                              pw.Text('   |   Tarih: ', style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: slate700)),
                              pw.Text('${session.sessionDate.day.toString().padLeft(2, '0')}.${session.sessionDate.month.toString().padLeft(2, '0')}.${session.sessionDate.year}', style: pw.TextStyle(font: font, fontSize: 9.5, color: slate700)),
                            ],
                          ),
                        ],
                      ),
                      pw.Row(
                        children: [
                          _buildStatBox('TOPLAM ÖĞRENCİ', '${roomStudents.length}', PdfColors.blue700, font, fontBold),
                          pw.SizedBox(width: 8),
                          _buildStatBox('KATILIM', '_____ / ${roomStudents.length}', PdfColors.orange700, font, fontBold),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(color: slate200, width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(28),   // Sıra
                    1: const pw.FlexColumnWidth(3.5),   // Adı Soyadı
                    2: const pw.FlexColumnWidth(2.2),   // TC No
                    3: const pw.FlexColumnWidth(2.5),   // Okul
                    4: const pw.FixedColumnWidth(42),   // Sınıf
                    5: const pw.FixedColumnWidth(45),   // Katıldı mı?
                    6: const pw.FixedColumnWidth(45),   // TC getirdi
                    7: const pw.FixedColumnWidth(45),   // Belge getirdi
                    8: const pw.FlexColumnWidth(2),     // İmza / Not
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: slate800),
                      children: [
                        _pdfHeaderCell('Sıra', fontBold),
                        _pdfHeaderCell('Adı Soyadı', fontBold),
                        _pdfHeaderCell('T.C. Kimlik', fontBold),
                        _pdfHeaderCell('Okulu', fontBold),
                        _pdfHeaderCell('Sınıf', fontBold),
                        _pdfHeaderCell('Katılım', fontBold),
                        _pdfHeaderCell('Kimlik', fontBold),
                        _pdfHeaderCell('G.Belgesi', fontBold),
                        _pdfHeaderCell('İmza / Not', fontBold),
                      ],
                    ),
                    ...List.generate(roomStudents.length, (idx) {
                      final s = roomStudents[idx];
                      final isEven = idx.isEven;
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: isEven ? PdfColors.white : slate50,
                        ),
                        children: [
                          _pdfDataCell('${s.seatNumber ?? idx + 1}', font, fontBold, isBold: true, align: pw.TextAlign.center),
                          _pdfDataCell(s.fullName, font, fontBold, isBold: true),
                          _pdfDataCell(s.studentTcNo, font, fontBold, align: pw.TextAlign.center),
                          _pdfDataCell(s.currentSchool, font, fontBold),
                          _pdfDataCell(s.gradeLevel == 'Mezun' ? 'Mezun' : '${s.gradeLevel}. Sınıf', font, fontBold, align: pw.TextAlign.center),
                          _pdfCheckboxCell(), // Katıldı
                          _pdfCheckboxCell(), // TC getirdi
                          _pdfCheckboxCell(), // Belge getirdi
                          _pdfDataCell('', font, fontBold),   // İmza / Not (boş)
                        ],
                      );
                    }),
                  ],
                ),
              ],
            ),
          );
        }
      } else {
        // Alphabetical List (All students)
        final sortedStudents = regs.where((r) => r.assignedRoomId != null).toList();
        sortedStudents.sort((a, b) => a.fullName.compareTo(b.fullName));

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            header: (context) => pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.orange500, width: 1)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    widget.exam.title.toUpperCase(),
                    style: pw.TextStyle(font: fontBold, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
                  ),
                  pw.Text(
                    'GENEL ÖĞRENCİ LİSTESİ (A-Z)',
                    style: pw.TextStyle(font: fontBold, fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: slate800),
                  ),
                ],
              ),
            ),
            footer: (context) => pw.Container(
              margin: const pw.EdgeInsets.only(top: 12),
              padding: const pw.EdgeInsets.only(top: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('eduKN Sınav Yönetim Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(
                    'Sayfa ${context.pageNumber}/${context.pagesCount}',
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
            build: (context) => [
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                margin: const pw.EdgeInsets.only(bottom: 14),
                decoration: pw.BoxDecoration(
                  color: slate50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'A-Z ÖĞRENCİ SALON SORGULAMA LİSTESİ',
                      style: pw.TextStyle(font: fontBold, fontSize: 12, fontWeight: pw.FontWeight.bold, color: slate900),
                    ),
                    pw.Text(
                      'Toplam Öğrenci: ${sortedStudents.length}',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
                    ),
                  ],
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(color: slate200, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(30),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(65),
                  3: const pw.FixedColumnWidth(55),
                  4: const pw.FlexColumnWidth(2.5),
                  5: const pw.FlexColumnWidth(2.5),
                  6: const pw.FixedColumnWidth(45),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: slate800),
                    children: [
                      _pdfHeaderCell('No', fontBold),
                      _pdfHeaderCell('Öğrenci Adı Soyadı', fontBold),
                      _pdfHeaderCell('Giriş Kodu', fontBold),
                      _pdfHeaderCell('Sınıf Seviyesi', fontBold),
                      _pdfHeaderCell('Atanan Salon', fontBold),
                      _pdfHeaderCell('Mevcut Okulu', fontBold),
                      _pdfHeaderCell('Sıra No', fontBold),
                    ],
                  ),
                  ...List.generate(sortedStudents.length, (idx) {
                    final s = sortedStudents[idx];
                    final isEven = idx.isEven;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? PdfColors.white : slate50,
                      ),
                      children: [
                        _pdfDataCell('${idx + 1}', font, fontBold, align: pw.TextAlign.center),
                        _pdfDataCell(s.fullName, font, fontBold, isBold: true),
                        _pdfDataCell(s.examEntryCode ?? '-', font, fontBold, isBold: true, align: pw.TextAlign.center),
                        _pdfDataCell(s.gradeLevel == 'Mezun' ? 'Mezun' : '${s.gradeLevel}. Sınıf', font, fontBold, align: pw.TextAlign.center),
                        _pdfDataCell(s.assignedRoomName ?? 'Salonsuz (Atanmadı)', font, fontBold, isBold: true, align: pw.TextAlign.center),
                        _pdfDataCell(s.currentSchool, font, fontBold),
                        _pdfDataCell(s.seatNumber != null ? '${s.seatNumber}' : '-', font, fontBold, isBold: true, align: pw.TextAlign.center),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: sortByRoom ? 'Salon_Sirali_Yoklama_Listesi' : 'Isim_Sirali_Salon_Listesi',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF oluşturma hatası: $e'), backgroundColor: Colors.red),
      );
    }
  }

  static pw.Widget _buildStatBox(String label, String value, PdfColor color, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColor.fromHex('#e2e8f0'), width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: fontBold, fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#64748b')),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(font: fontBold, fontSize: 12, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfHeaderCell(String text, pw.Font fontBold) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
          textAlign: pw.TextAlign.center,
        ),
      );

  pw.Widget _pdfDataCell(String text, pw.Font font, pw.Font fontBold, {bool isBold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: isBold ? fontBold : font,
            fontSize: 7.5,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColor.fromHex('#0f172a'),
          ),
          textAlign: align,
          maxLines: 2,
        ),
      );

  pw.Widget _pdfCheckboxCell() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Center(
          child: pw.Container(
            width: 11, height: 11,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromHex('#94a3b8'), width: 0.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),
        ),
      );

  Future<pw.Font> _loadRegularFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Local Roboto-Regular asset failed: $e. Trying CDN...');
      try {
        final response = await http.get(Uri.parse('https://cdn.jsdelivr.net/npm/roboto-fontface/fonts/roboto/Roboto-Regular.ttf'));
        if (response.statusCode == 200) {
          return pw.Font.ttf(ByteData.view(response.bodyBytes.buffer));
        }
      } catch (cdnError) {
        debugPrint('CDN Roboto-Regular failed: $cdnError');
      }
      try {
        return await PdfGoogleFonts.robotoRegular();
      } catch (gfontError) {
        debugPrint('Google Fonts Regular fallback failed: $gfontError');
      }
      return pw.Font.helvetica();
    }
  }

  Future<pw.Font> _loadBoldFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Local Roboto-Bold asset failed: $e. Trying CDN...');
      try {
        final response = await http.get(Uri.parse('https://cdn.jsdelivr.net/npm/roboto-fontface/fonts/roboto/Roboto-Bold.ttf'));
        if (response.statusCode == 200) {
          return pw.Font.ttf(ByteData.view(response.bodyBytes.buffer));
        }
      } catch (cdnError) {
        debugPrint('CDN Roboto-Bold failed: $cdnError');
      }
      try {
        return await PdfGoogleFonts.robotoBold();
      } catch (gfontError) {
        debugPrint('Google Fonts Bold fallback failed: $gfontError');
      }
      return pw.Font.helveticaBold();
    }
  }
}
