import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';

class ExternalExamEntryCardScreen extends StatefulWidget {
  final ExternalExam exam;
  final List<ExternalExamRegistration> registrations;

  const ExternalExamEntryCardScreen({
    Key? key,
    required this.exam,
    required this.registrations,
  }) : super(key: key);

  @override
  State<ExternalExamEntryCardScreen> createState() =>
      _ExternalExamEntryCardScreenState();
}

class _ExternalExamEntryCardScreenState
    extends State<ExternalExamEntryCardScreen> {
  static const _primaryColor = Color(0xFFF57C00);

  String _searchQuery = '';
  String? _selectedSession;
  String? _selectedGrade;
  String? _selectedRoom;
  String _sortBy = 'name'; // 'name', 'room_seat', 'code'

  List<ExternalExamRegistration> get _filteredRegistrations {
    return widget.registrations.where((reg) {
      // Filter by search query
      final nameMatch =
          '${reg.studentName} ${reg.studentSurname}'
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (reg.examEntryCode ?? '')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());

      // Filter by session
      final sessionMatch =
          _selectedSession == null || reg.sessionId == _selectedSession;

      // Filter by grade
      final gradeMatch =
          _selectedGrade == null || reg.gradeLevel == _selectedGrade;

      // Filter by room
      final roomMatch =
          _selectedRoom == null || reg.assignedRoomName == _selectedRoom;

      return nameMatch && sessionMatch && gradeMatch && roomMatch;
    }).toList()
      ..sort((a, b) {
        if (_sortBy == 'room_seat') {
          final roomCompare = (a.assignedRoomName ?? '')
              .compareTo(b.assignedRoomName ?? '');
          if (roomCompare != 0) return roomCompare;
          return (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0);
        } else if (_sortBy == 'code') {
          return (a.examEntryCode ?? '').compareTo(b.examEntryCode ?? '');
        } else {
          return '${a.studentName} ${a.studentSurname}'
              .compareTo('${b.studentName} ${b.studentSurname}');
        }
      });
  }

  List<String> get _sessions {
    final list = widget.registrations.map((r) => r.sessionId).toSet().toList();
    list.sort();
    return list;
  }

  List<String> get _grades {
    final list = widget.registrations.map((r) => r.gradeLevel).toSet().toList();
    list.sort();
    return list;
  }

  List<String> get _rooms {
    final list = widget.registrations
        .map((r) => r.assignedRoomName)
        .whereType<String>()
        .toSet()
        .toList();
    list.sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRegistrations;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Sınav Giriş Belgeleri',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
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
      body: Column(
        children: [
          _buildFilterBar(isMobile),
          _buildPrintActionsBar(filtered),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : isMobile
                    ? _buildMobileList(filtered)
                    : _buildWebGrid(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Öğrenci adı veya giriş kodu ile ara...',
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
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.sort_rounded, color: _primaryColor),
                  tooltip: 'Sıralama Seçenekleri',
                  onSelected: (val) => setState(() => _sortBy = val),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'name',
                      child: Row(
                        children: [
                          Icon(Icons.abc_rounded, color: _sortBy == 'name' ? _primaryColor : Colors.grey),
                          const SizedBox(width: 8),
                          Text('Öğrenci Adı A-Z', style: GoogleFonts.inter(fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'room_seat',
                      child: Row(
                        children: [
                          Icon(Icons.meeting_room_rounded, color: _sortBy == 'room_seat' ? _primaryColor : Colors.grey),
                          const SizedBox(width: 8),
                          Text('Salon ve Sıra No', style: GoogleFonts.inter(fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'code',
                      child: Row(
                        children: [
                          Icon(Icons.badge_rounded, color: _sortBy == 'code' ? _primaryColor : Colors.grey),
                          const SizedBox(width: 8),
                          Text('Giriş Kodu Sıralı', style: GoogleFonts.inter(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Session filter
                _buildFilterChip(
                  label: _selectedSession != null ? 'Seans filtreli' : 'Tüm Seanslar',
                  value: _selectedSession,
                  items: _sessions,
                  onSelected: (val) => setState(() => _selectedSession = val),
                  onClear: () => setState(() => _selectedSession = null),
                ),
                const SizedBox(width: 8),
                // Grade filter
                _buildFilterChip(
                  label: _selectedGrade != null ? (_selectedGrade == 'Mezun' ? 'Mezun filtreli' : 'Sınıf filtreli: $_selectedGrade') : 'Tüm Sınıflar',
                  value: _selectedGrade,
                  items: _grades,
                  onSelected: (val) => setState(() => _selectedGrade = val),
                  onClear: () => setState(() => _selectedGrade = null),
                ),
                const SizedBox(width: 8),
                // Room filter
                _buildFilterChip(
                  label: _selectedRoom != null ? 'Salon filtreli: $_selectedRoom' : 'Tüm Salonlar',
                  value: _selectedRoom,
                  items: _rooms,
                  onSelected: (val) => setState(() => _selectedRoom = val),
                  onClear: () => setState(() => _selectedRoom = null),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onSelected,
    required VoidCallback onClear,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (ctx) => [
        const PopupMenuItem<String>(
          value: null,
          child: Text('Tümünü Göster'),
        ),
        ...items.map((item) => PopupMenuItem<String>(
              value: item,
              child: Text(item),
            )),
      ],
      child: Chip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value ?? label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: value != null ? _primaryColor : Colors.grey.shade700,
                fontWeight: value != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  onClear();
                },
                child: const Icon(Icons.close_rounded, size: 14, color: _primaryColor),
              ),
            ] else ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.grey),
            ]
          ],
        ),
        backgroundColor: value != null ? Colors.orange.shade50 : const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: value != null ? Colors.orange.shade200 : Colors.transparent),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildPrintActionsBar(List<ExternalExamRegistration> filtered) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${filtered.length} Kayıt Gösteriliyor',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          Wrap(
            spacing: 8,
            children: [
              IconButton(
                icon: const Icon(Icons.print_rounded, color: _primaryColor),
                tooltip: 'Toplu Giriş Belgesi Yazdır (PDF)',
                onPressed: filtered.isEmpty ? null : () => _printEntryCardsPdf(filtered),
              ),
              IconButton(
                icon: const Icon(Icons.assignment_turned_in_rounded, color: Colors.teal),
                tooltip: 'Salon Sıralı Yoklama Listesi Bas (PDF)',
                onPressed: filtered.isEmpty ? null : () => _printRoomListsPdf(filtered),
              ),
              IconButton(
                icon: const Icon(Icons.list_alt_rounded, color: Colors.blue),
                tooltip: 'Öğrenci Adı Sıralı Liste Bas (PDF)',
                onPressed: filtered.isEmpty ? null : () => _printAlphabeticalListPdf(filtered),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.badge_outlined, size: 48, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            'Sonuç Bulunamadı',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 6),
          Text(
            'Kriterlerinize uygun giriş belgesi atanmış öğrenci bulunmuyor.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList(List<ExternalExamRegistration> list) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final reg = list[idx];
        return _buildEntryCardWidget(reg);
      },
    );
  }

  Widget _buildWebGrid(List<ExternalExamRegistration> list) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 450,
        mainAxisExtent: 220,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final reg = list[idx];
        return _buildEntryCardWidget(reg);
      },
    );
  }

  Widget _buildEntryCardWidget(ExternalExamRegistration reg) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.exam.title.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'SINAV GİRİŞ BELGESİ',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    reg.examEntryCode ?? 'KOD YOK',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCardInfoRow('Öğrenci:', reg.fullName, isBold: true),
                        _buildCardInfoRow('T.C. Kimlik:', reg.displayTcNo),
                        _buildCardInfoRow('Sınıf Seviyesi:', reg.gradeLevel == 'Mezun' ? 'Mezun' : '${reg.gradeLevel}. Sınıf'),
                        _buildCardInfoRow('Mevcut Okul:', reg.currentSchool, maxLines: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, color: Colors.grey.shade200),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCardInfoRow(
                          'Sınav Salonu:',
                          reg.assignedRoomName ?? 'Atanmadı',
                          isHighlight: reg.assignedRoomName != null,
                        ),
                        _buildCardInfoRow(
                          'Sıra Numarası:',
                          reg.seatNumber != null ? '${reg.seatNumber}. Sıra' : 'Atanmadı',
                          isHighlight: reg.seatNumber != null,
                        ),
                        _buildCardInfoRow(
                          'Salon Kodu:',
                          reg.assignedRoomCode ?? '-',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lütfen sınav saatinden 15 dk önce salonda olunuz.',
                  style: GoogleFonts.inter(fontSize: 8, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                ),
                IconButton(
                  icon: const Icon(Icons.print_rounded, size: 16, color: _primaryColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _printSingleEntryCard(reg),
                  tooltip: 'Yazdır',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardInfoRow(String label, String value, {bool isBold = false, bool isHighlight = false, int maxLines = 2}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 9, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isBold || isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight
                ? _primaryColor
                : isBold
                    ? Colors.grey.shade800
                    : Colors.grey.shade700,
          ),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // PDF Generation Methods using PDF and Printing packages

  Future<void> _printSingleEntryCard(ExternalExamRegistration reg) async {
    await _printEntryCardsPdf([reg]);
  }

  Future<void> _printEntryCardsPdf(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      try {
        font = await PdfGoogleFonts.openSansRegular();
        fontBold = await PdfGoogleFonts.openSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      // 4 cards per A4 page
      final double cardWidth = 270;
      final double cardHeight = 180;

      for (int i = 0; i < list.length; i += 4) {
        final chunk = list.skip(i).take(4).toList();

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            build: (pw.Context context) {
              return pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _buildPdfCard(chunk[0], cardWidth, cardHeight),
                      if (chunk.length > 1)
                        _buildPdfCard(chunk[1], cardWidth, cardHeight)
                      else
                        pw.Container(width: cardWidth, height: cardHeight),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  if (chunk.length > 2)
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPdfCard(chunk[2], cardWidth, cardHeight),
                        if (chunk.length > 3)
                          _buildPdfCard(chunk[3], cardWidth, cardHeight)
                        else
                          pw.Container(width: cardWidth, height: cardHeight),
                      ],
                    )
                ],
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'sinav_giris_belgeleri_${widget.exam.id}.pdf',
      );
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  pw.Widget _buildPdfCard(ExternalExamRegistration reg, double width, double height) {
    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange900, width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    widget.exam.title.toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.orange900),
                  ),
                  pw.Text(
                    'SINAV GİRİŞ BELGESİ',
                    style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.orange100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  reg.examEntryCode ?? '',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.orange900),
                ),
              ),
            ],
          ),
          pw.Divider(thickness: 0.5, color: PdfColors.orange300, height: 8),
          pw.Expanded(
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPdfCardRow('Öğrenci Adı Soyadı:', reg.fullName, isBold: true),
                      _buildPdfCardRow('T.C. Kimlik No:', reg.displayTcNo),
                      _buildPdfCardRow('Sınıf Seviyesi:', reg.gradeLevel == 'Mezun' ? 'Mezun' : '${reg.gradeLevel}. Sınıf'),
                      _buildPdfCardRow('Mevcut Okulu:', reg.currentSchool),
                    ],
                  ),
                ),
                pw.Container(width: 0.5, color: PdfColors.grey300),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPdfCardRow('Sınav Salonu:', reg.assignedRoomName ?? 'Atanmadı', isHighlight: true),
                      _buildPdfCardRow('Sıra Numarası:', reg.seatNumber != null ? '${reg.seatNumber}. Sıra' : 'Atanmadı', isHighlight: true),
                      _buildPdfCardRow('Salon Kodu:', reg.assignedRoomCode ?? '-'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 0.5, color: PdfColors.grey300, height: 6),
          pw.Text(
            'Lütfen sınav saatinden 15 dakika önce sınav giriş belgesi ve kimliğinizle birlikte salonda hazır bulununuz.',
            style: pw.TextStyle(fontSize: 5, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfCardRow(String label, String value, {bool isBold = false, bool isHighlight = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey500)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: isBold || isHighlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isHighlight ? PdfColors.orange900 : PdfColors.black,
          ),
        ),
      ],
    );
  }

  // Room lists printing: Ordered by room then seat number
  Future<void> _printRoomListsPdf(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      try {
        font = await PdfGoogleFonts.openSansRegular();
        fontBold = await PdfGoogleFonts.openSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      // Group students by room
      final Map<String, List<ExternalExamRegistration>> grouped = {};
      for (var reg in list) {
        final roomName = reg.assignedRoomName ?? 'Atanmamış';
        grouped.putIfAbsent(roomName, () => []).add(reg);
      }

      for (var roomName in grouped.keys) {
        final roomStudents = grouped[roomName]!;
        // Sort by seat number
        roomStudents.sort((a, b) => (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0));

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            header: (context) => pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text('${widget.exam.title} - SALON YOKLAMA LİSTESİ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ),
            build: (pw.Context context) {
              return [
                pw.Text('SALON: $roomName', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                pw.SizedBox(height: 4),
                pw.Text('Toplam Öğrenci Sayısı: ${roomStudents.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.SizedBox(height: 15),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(40),
                    1: const pw.FixedColumnWidth(80),
                    2: const pw.FlexColumnWidth(3),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FixedColumnWidth(50),
                    5: const pw.FixedColumnWidth(60),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.orange100),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sıra No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Giriş Kodu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Adı Soyadı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Mevcut Okul', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sınıf', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('İmza', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      ],
                    ),
                    ...roomStudents.map((s) => pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${s.seatNumber ?? "-"}', style: const pw.TextStyle(fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.examEntryCode ?? '', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.fullName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.currentSchool, style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(s.gradeLevel == 'Mezun' ? 'Mezun' : '${s.gradeLevel}. Sınıf', style: const pw.TextStyle(fontSize: 9))),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('', style: const pw.TextStyle(fontSize: 9))),
                          ],
                        )),
                  ],
                ),
              ];
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'salon_yoklama_listeleri_${widget.exam.id}.pdf',
      );
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  // Alphabetical list of all students showing where they are seated
  Future<void> _printAlphabeticalListPdf(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      try {
        font = await PdfGoogleFonts.openSansRegular();
        fontBold = await PdfGoogleFonts.openSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      // Sort alphabetically
      final sorted = List<ExternalExamRegistration>.from(list)
        ..sort((a, b) => '${a.studentName} ${a.studentSurname}'.compareTo('${b.studentName} ${b.studentSurname}'));

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(35),
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          header: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text('${widget.exam.title} - GENEL AD SIRALI ÖĞRENCİ LİSTESİ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
          build: (pw.Context context) {
            return [
              pw.Text('GENEL ÖĞRENCİ LİSTESİ (A-Z)', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
              pw.SizedBox(height: 4),
              pw.Text('Toplam Öğrenci Sayısı: ${sorted.length}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.SizedBox(height: 15),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(30),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(60),
                  3: const pw.FixedColumnWidth(50),
                  4: const pw.FlexColumnWidth(2),
                  5: const pw.FlexColumnWidth(2),
                  6: const pw.FixedColumnWidth(40),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.orange100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Öğrenci Adı Soyadı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Giriş Kodu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Sınıf', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Sınav Salonu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Okulu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Sıra No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    ],
                  ),
                  ...List.generate(sorted.length, (idx) {
                    final s = sorted[idx];
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${idx + 1}', style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.fullName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.examEntryCode ?? '', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.gradeLevel == 'Mezun' ? 'Mezun' : '${s.gradeLevel}. Sınıf', style: const pw.TextStyle(fontSize: 8.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.assignedRoomName ?? 'Atanmadı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.orange900))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.currentSchool, style: const pw.TextStyle(fontSize: 8))),
                        pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(s.seatNumber != null ? '${s.seatNumber}' : '-', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'ad_sirali_ogrenci_listesi_${widget.exam.id}.pdf',
      );
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  void _showErrorSnackBar(dynamic err) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Yazdırma hatası oluştu: $err', style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: Colors.red,
      ),
    );
  }
}
