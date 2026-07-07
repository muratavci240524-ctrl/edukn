import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
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

  String _schoolName = 'eduKN EĞİTİM KURUMLARI';

  // ─── Font Cache: bir kez yükle, hep kullan ───────────────────────────────
  pw.Font? _cachedFont;
  pw.Font? _cachedFontBold;
  bool _fontsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSchoolName();
    _autoAssignCodesToEmpty();
    _preloadFonts(); // Fontları arka planda önceden yükle
  }

  /// Fontları background'da yükleyip cache'le — PDF çok hızlanır
  Future<void> _preloadFonts() async {
    if (_fontsLoading || (_cachedFont != null && _cachedFontBold != null)) return;
    _fontsLoading = true;
    try {
      final results = await Future.wait([
        _loadRegularFontRaw(),
        _loadBoldFontRaw(),
      ]);
      _cachedFont = results[0];
      _cachedFontBold = results[1];
    } catch (e) {
      debugPrint('Font preload failed: $e');
    } finally {
      _fontsLoading = false;
    }
  }

  Future<void> _loadSchoolName() async {
    try {
      if (widget.exam.schoolId.isNotEmpty) {
        final schoolDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.exam.schoolId)
            .get();
        if (schoolDoc.exists) {
          final name = schoolDoc.data()?['schoolName'] as String?;
          if (name != null && name.isNotEmpty) {
            setState(() {
              _schoolName = name;
            });
            return;
          }
        }
      }
      if (widget.exam.institutionId.isNotEmpty) {
        final instDoc = await FirebaseFirestore.instance
            .collection('institutions')
            .doc(widget.exam.institutionId)
            .get();
        if (instDoc.exists) {
          final name = instDoc.data()?['name'] ?? instDoc.data()?['institutionName'] as String?;
          if (name != null && name.isNotEmpty) {
            setState(() {
              _schoolName = name;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading school/institution name: $e');
    }
  }

  Future<void> _autoAssignCodesToEmpty() async {
    try {
      final emptyCodes = widget.registrations
          .where((r) => r.examEntryCode == null || r.examEntryCode!.isEmpty)
          .toList();
      if (emptyCodes.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      final year = DateTime.now().year;
      int startIndex = widget.registrations.length - emptyCodes.length + 1;

      for (var reg in emptyCodes) {
        final randomDigits = Random().nextInt(90) + 10;
        final entryCode = 'EKS-$year-${startIndex.toString().padLeft(4, '0')}-$randomDigits';
        final docRef = FirebaseFirestore.instance
            .collection('external_exam_registrations')
            .doc(reg.id);
        batch.update(docRef, {
          'examEntryCode': entryCode,
        });
        startIndex++;
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error auto assigning codes: $e');
    }
  }

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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _printActionBtn(
                  icon: Icons.badge_rounded,
                  label: 'Giriş Belgeleri',
                  color: _primaryColor,
                  tooltip: 'Toplu Giriş Belgesi (PDF)',
                  onPressed: filtered.isEmpty ? null : () => _showPrintOptionDialog(filtered),
                ),
                const SizedBox(width: 8),
                _printActionBtn(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Salon Yoklama',
                  color: Colors.teal,
                  tooltip: 'Salon Sıralı Yoklama Listesi (PDF)',
                  onPressed: filtered.isEmpty ? null : () => _printRoomListsPdf(filtered),
                ),
                const SizedBox(width: 8),
                _printActionBtn(
                  icon: Icons.sort_by_alpha_rounded,
                  label: 'İsim Sıralı Liste',
                  color: Colors.indigo,
                  tooltip: 'Öğrenci Adı Sıralı Liste (PDF)',
                  onPressed: filtered.isEmpty ? null : () => _printAlphabeticalListPdf(filtered),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _printActionBtn({required IconData icon, required String label, required Color color, String? tooltip, VoidCallback? onPressed}) {
    return Tooltip(
      message: tooltip ?? label,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
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
        return SizedBox(
          height: 245,
          child: _buildEntryCardWidget(reg),
        );
      },
    );
  }

  Widget _buildWebGrid(List<ExternalExamRegistration> list) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 450,
        mainAxisExtent: 245,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const Divider(height: 10),
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
                        _buildCardInfoRow('T.C. Kimlik:', reg.studentTcNo),
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
    await _withPdfLoadingOverlay(
      () => _printSingleStudentA4CardsPdf([reg]),
      label: 'Giriş belgesi hazırlanıyor...',
    );
  }

  Future<void> _printEntryCardsPdf(List<ExternalExamRegistration> list) async {
    await _withPdfLoadingOverlay(
      () => _printEntryCardsPdfInternal(list),
      label: '${list.length} öğrencinin çoklu kartı hazırlanıyor...',
    );
  }

  Future<void> _printEntryCardsPdfInternal(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      font = await _loadRegularFont();
      fontBold = await _loadBoldFont();

      // 8 cards per A4 page (2 columns x 4 rows)
      final double cardWidth = 270;
      final double cardHeight = 175;

      for (int i = 0; i < list.length; i += 8) {
        final chunk = list.skip(i).take(8).toList();

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            build: (pw.Context context) {
              return pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  for (int r = 0; r < 4; r++) ...[
                    if (chunk.length > r * 2)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _buildPdfCard(chunk[r * 2], cardWidth, cardHeight, font, fontBold),
                          if (chunk.length > r * 2 + 1)
                            _buildPdfCard(chunk[r * 2 + 1], cardWidth, cardHeight, font, fontBold)
                          else
                            pw.Container(width: cardWidth, height: cardHeight),
                        ],
                      ),
                    if (r < 3 && chunk.length > (r + 1) * 2)
                      pw.SizedBox(height: 8),
                  ]
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

  pw.Widget _buildPdfCard(ExternalExamRegistration reg, double width, double height, pw.Font font, pw.Font fontBold) {
    return pw.Container(
      width: width,
      height: height,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange900, width: 1.2),
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
                    _schoolName.toUpperCase(),
                    style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 6.5, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    widget.exam.title.toUpperCase(),
                    style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.orange900),
                  ),
                  pw.Text(
                    'SINAV GİRİŞ BELGESİ',
                    style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Row(
                children: [
                  pw.Container(
                    width: 20,
                    height: 20,
                    margin: const pw.EdgeInsets.only(right: 6),
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: reg.examEntryCode ?? reg.id ?? reg.studentTcNo,
                      drawText: false,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.orange100,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Text(
                      reg.examEntryCode ?? '',
                      style: pw.TextStyle(font: fontBold, fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.orange900),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 0.5, color: PdfColors.orange300, height: 6),
          pw.Expanded(
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPdfCardRow('Öğrenci Adı Soyadı:', reg.fullName, font, fontBold, isBold: true),
                      _buildPdfCardRow('T.C. Kimlik No:', reg.studentTcNo, font, fontBold),
                      _buildPdfCardRow('Sınıf Seviyesi:', reg.gradeLevel == 'Mezun' ? 'Mezun' : '${reg.gradeLevel}. Sınıf', font, fontBold),
                      _buildPdfCardRow('Mevcut Okulu:', reg.currentSchool, font, fontBold),
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
                      _buildPdfCardRow('Sınav Salonu:', reg.assignedRoomName ?? 'Atanmadı', font, fontBold, isHighlight: true),
                      _buildPdfCardRow('Sıra Numarası:', reg.seatNumber != null ? '${reg.seatNumber}. Sıra' : 'Atanmadı', font, fontBold, isHighlight: true),
                      _buildPdfCardRow('Salon Kodu:', reg.assignedRoomCode ?? '-', font, fontBold),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Divider(thickness: 0.5, color: PdfColors.grey300, height: 4),
          pw.Text(
            'Lütfen sınav saatinden 15 dakika önce sınav giriş belgesi ve kimliğinizle birlikte salonda hazır bulununuz.',
            style: pw.TextStyle(font: font, fontSize: 4.5, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfCardRow(String label, String value, pw.Font font, pw.Font fontBold, {bool isBold = false, bool isHighlight = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 5.5, color: PdfColors.grey500)),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: isBold || isHighlight ? fontBold : font,
            fontSize: 7,
            fontWeight: isBold || isHighlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isHighlight ? PdfColors.orange900 : PdfColors.black,
          ),
        ),
      ],
    );
  }

  // Room lists printing: Ordered by room then seat number - Premium design
  Future<void> _printRoomListsPdf(List<ExternalExamRegistration> list) async {
    await _withPdfLoadingOverlay(
      () => _printRoomListsPdfInternal(list),
      label: 'Salon yoklama listeleri hazırlanıyor...',
    );
  }

  Future<void> _printRoomListsPdfInternal(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      font = await _loadRegularFont();
      fontBold = await _loadBoldFont();

      // Group students by room
      final Map<String, List<ExternalExamRegistration>> grouped = {};
      for (var reg in list) {
        final roomName = reg.assignedRoomName ?? 'Atanmamış';
        grouped.putIfAbsent(roomName, () => []).add(reg);
      }
      final sortedRoomNames = grouped.keys.toList()..sort();

      for (var roomName in sortedRoomNames) {
        final roomStudents = List<ExternalExamRegistration>.from(grouped[roomName]!)
          ..sort((a, b) => (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0));

        final session = widget.exam.applicationSessions.firstWhere(
          (s) => roomStudents.isNotEmpty && s.id == roomStudents.first.sessionId,
          orElse: () => widget.exam.applicationSessions.isNotEmpty
              ? widget.exam.applicationSessions.first
              : ApplicationSession(id: '', sessionDate: DateTime.now(), startTime: '', endTime: '', gradeLevels: [], gradeLevelQuotas: {}),
        );

        final slate800 = PdfColor.fromHex('#1e293b');
        final slate700 = PdfColor.fromHex('#334155');
        final slate50 = PdfColor.fromHex('#f8fafc');
        final slate100 = PdfColor.fromHex('#f1f5f9');
        final slate200 = PdfColor.fromHex('#e2e8f0');

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
            build: (pw.Context context) {
              return [
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
                    // Header row
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
                    // Student rows
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

  // Alphabetical list of all students showing where they are seated - Premium design
  Future<void> _printAlphabeticalListPdf(List<ExternalExamRegistration> list) async {
    await _withPdfLoadingOverlay(
      () => _printAlphabeticalListPdfInternal(list),
      label: 'İsim sıralı liste hazırlanıyor...',
    );
  }

  Future<void> _printAlphabeticalListPdfInternal(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      font = await _loadRegularFont();
      fontBold = await _loadBoldFont();

      // Sort alphabetically
      final sorted = List<ExternalExamRegistration>.from(list)
        ..sort((a, b) => '${a.studentName} ${a.studentSurname}'.compareTo('${b.studentName} ${b.studentSurname}'));

      final slate800 = PdfColor.fromHex('#1e293b');
      final slate900 = PdfColor.fromHex('#0f172a');
      final slate200 = PdfColor.fromHex('#e2e8f0');
      final slate50 = PdfColor.fromHex('#f8fafc');

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
          build: (pw.Context context) {
            return [
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
                      'Toplam Öğrenci: ${sorted.length}',
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
                  ...List.generate(sorted.length, (idx) {
                    final s = sorted[idx];
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

  void _showPrintOptionDialog(List<ExternalExamRegistration> filtered) {
    String? _printFormat; // 'single' | 'multi'
    String _printSort = 'name'; // 'name' | 'school' | 'room_seat' | 'grade'

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          // Sıralama uygulanmış liste
          List<ExternalExamRegistration> _getSortedList() {
            final sorted = List<ExternalExamRegistration>.from(filtered);
            switch (_printSort) {
              case 'school':
                sorted.sort((a, b) {
                  final schoolCmp = a.currentSchool.compareTo(b.currentSchool);
                  if (schoolCmp != 0) return schoolCmp;
                  return '${a.studentName} ${a.studentSurname}'
                      .compareTo('${b.studentName} ${b.studentSurname}');
                });
                break;
              case 'room_seat':
                sorted.sort((a, b) {
                  final roomCmp = (a.assignedRoomName ?? '').compareTo(b.assignedRoomName ?? '');
                  if (roomCmp != 0) return roomCmp;
                  return (a.seatNumber ?? 0).compareTo(b.seatNumber ?? 0);
                });
                break;
              case 'grade':
                sorted.sort((a, b) {
                  final gradeCmp = a.gradeLevel.compareTo(b.gradeLevel);
                  if (gradeCmp != 0) return gradeCmp;
                  return '${a.studentName} ${a.studentSurname}'
                      .compareTo('${b.studentName} ${b.studentSurname}');
                });
                break;
              default: // 'name'
                sorted.sort((a, b) => '${a.studentName} ${a.studentSurname}'
                    .compareTo('${b.studentName} ${b.studentSurname}'));
            }
            return sorted;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print_rounded, color: _primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toplu Giriş Belgesi', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${filtered.length} öğrenci', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    // ── BÖLÜM 1: FORMAT ────────────────────────────────
                    _buildDialogSectionHeader('1. Belge Formatı', Icons.insert_drive_file_outlined),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFormatCard(
                            selected: _printFormat == 'single',
                            icon: Icons.insert_drive_file_outlined,
                            title: 'Tekli (A4)',
                            subtitle: 'Sayfa başına 1 öğrenci',
                            color: _primaryColor,
                            onTap: () => setDlgState(() => _printFormat = 'single'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildFormatCard(
                            selected: _printFormat == 'multi',
                            icon: Icons.grid_view_rounded,
                            title: 'Çoklu (2×4)',
                            subtitle: 'Sayfa başına 8 kart',
                            color: Colors.teal,
                            onTap: () => setDlgState(() => _printFormat = 'multi'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // ── BÖLÜM 2: SIRALAMA ──────────────────────────────
                    _buildDialogSectionHeader('2. Yazdırma Sıralaması', Icons.sort_rounded),
                    const SizedBox(height: 10),

                    // İsim sıralı
                    _buildSortOptionTile(
                      selected: _printSort == 'name',
                      icon: Icons.abc_rounded,
                      title: 'İsim Sıralı (A-Z)',
                      subtitle: 'Öğrenci adı soyadına göre alfabetik',
                      onTap: () => setDlgState(() => _printSort = 'name'),
                    ),
                    const SizedBox(height: 6),

                    // Okul sıralı
                    _buildSortOptionTile(
                      selected: _printSort == 'school',
                      icon: Icons.school_rounded,
                      title: 'Okul Sıralı',
                      subtitle: 'Kayıtlı okula göre gruplu, her okul içinde isim sıralı',
                      onTap: () => setDlgState(() => _printSort = 'school'),
                    ),
                    const SizedBox(height: 6),

                    // Salon sıralı
                    _buildSortOptionTile(
                      selected: _printSort == 'room_seat',
                      icon: Icons.meeting_room_rounded,
                      title: 'Salon ve Sıra Numarası',
                      subtitle: 'Salon adına göre, her salonda sıra numarasına göre',
                      onTap: () => setDlgState(() => _printSort = 'room_seat'),
                    ),
                    const SizedBox(height: 6),

                    // Sınıf sıralı
                    _buildSortOptionTile(
                      selected: _printSort == 'grade',
                      icon: Icons.class_rounded,
                      title: 'Sınıf Seviyesi Sıralı',
                      subtitle: 'Sınıf seviyesine göre gruplu, her sınıf içinde isim sıralı',
                      onTap: () => setDlgState(() => _printSort = 'grade'),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade600)),
              ),
              ElevatedButton.icon(
                onPressed: _printFormat == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        final sortedList = _getSortedList();
                        if (_printFormat == 'single') {
                          _withPdfLoadingOverlay(
                            () => _printSingleStudentA4CardsPdf(sortedList),
                            label: '${sortedList.length} tekli giriş belgesi hazırlanıyor...',
                          );
                        } else {
                          _printEntryCardsPdf(sortedList);
                        }
                      },

                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: Text('Yazdır', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDialogSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _primaryColor),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildFormatCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.07) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.grey.shade400, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? color : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOptionTile({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _primaryColor : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? _primaryColor.withOpacity(0.12) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: selected ? _primaryColor : Colors.grey.shade400,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: selected ? const Color(0xFF1E293B) : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _primaryColor, size: 20),
          ],
        ),
      ),
    );
  }



  Future<void> _printSingleStudentA4CardsPdf(List<ExternalExamRegistration> list) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font fontBold;

      font = await _loadRegularFont();
      fontBold = await _loadBoldFont();

      final primaryHex = '#f57c00';
      final primaryColor = PdfColor.fromHex(primaryHex);
      final darkColor = PdfColor.fromHex('#1e293b');
      final greyColor = PdfColor.fromHex('#64748b');
      final lightBg = PdfColor.fromHex('#f8fafc');
      final borderClr = PdfColor.fromHex('#e2e8f0');

      for (var reg in list) {
        final session = widget.exam.applicationSessions.firstWhere(
          (s) => s.id == reg.sessionId,
          orElse: () => widget.exam.applicationSessions.isNotEmpty
              ? widget.exam.applicationSessions.first
              : ApplicationSession(id: '', sessionDate: DateTime.now(), startTime: '', endTime: '', gradeLevels: [], gradeLevelQuotas: {}),
        );

        final dateStr = '${session.sessionDate.day.toString().padLeft(2, '0')}.${session.sessionDate.month.toString().padLeft(2, '0')}.${session.sessionDate.year}';
        final timeStr = session.startTimeForGrade(reg.gradeLevel) != ''
            ? '${session.startTimeForGrade(reg.gradeLevel)} – ${session.endTimeForGrade(reg.gradeLevel)}'
            : session.displayTime;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(36),
            theme: pw.ThemeData.withFont(base: font, bold: fontBold),
            build: (pw.Context context) {
              return pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: primaryColor, width: 2),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
                ),
                padding: const pw.EdgeInsets.all(28),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Header Block
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                _schoolName,
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: greyColor,
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                widget.exam.title.toUpperCase(),
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                  color: darkColor,
                                ),
                              ),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                'SINAV GİRİŞ BELGESİ',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Container(
                              width: 70,
                              height: 70,
                              padding: const pw.EdgeInsets.all(4),
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: borderClr, width: 1),
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                              ),
                              child: pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: reg.examEntryCode ?? reg.id ?? reg.studentTcNo,
                                drawText: false,
                              ),
                            ),
                            pw.SizedBox(height: 6),
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const pw.BoxDecoration(
                                color: PdfColors.orange100,
                                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                              ),
                              child: pw.Text(
                                reg.examEntryCode ?? '-',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 16),
                    pw.Divider(thickness: 1.5, color: primaryColor, height: 10),
                    pw.SizedBox(height: 16),

                    // Two Columns for Info
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Left Column: Candidate Info
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _buildA4SectionHeader('ADAY BİLGİLERİ', greyColor, fontBold),
                                pw.SizedBox(height: 12),
                                _buildA4InfoRow('Adı Soyadı:', reg.fullName, font, fontBold),
                                _buildA4InfoRow('T.C. Kimlik No:', reg.studentTcNo, font, font),
                                _buildA4InfoRow('Sınıf Seviyesi:', reg.gradeLevel == 'Mezun' ? 'Mezun' : '${reg.gradeLevel}. Sınıf', font, font),
                                _buildA4InfoRow('Kayıtlı Okulu:', reg.currentSchool, font, font),
                              ],
                            ),
                          ),
                          pw.VerticalDivider(thickness: 1, color: borderClr),
                          pw.SizedBox(width: 16),
                          // Right Column: Venue & Session Info
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                _buildA4SectionHeader('SINAV YERİ VE OTURUM BİLGİLERİ', greyColor, fontBold),
                                pw.SizedBox(height: 12),
                                _buildA4InfoRow('Sınav Salonu:', reg.assignedRoomName ?? 'Atanmadı', font, fontBold, isHighlight: true, highlightColor: primaryColor),
                                _buildA4InfoRow('Sıra Numarası:', reg.seatNumber != null ? '${reg.seatNumber}. Sıra' : 'Atanmadı', font, fontBold, isHighlight: true, highlightColor: primaryColor),
                                _buildA4InfoRow('Salon Kodu:', reg.assignedRoomCode ?? '-', font, font),
                                _buildA4InfoRow('Sınav Tarihi:', dateStr, font, font),
                                _buildA4InfoRow('Sınav Saati:', timeStr, font, font),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    pw.SizedBox(height: 20),
                    // Info Rules Card
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: lightBg,
                        border: pw.Border.all(color: borderClr, width: 1),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'SINAV KURALLARI VE ÖNEMLİ BİLGİLER',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: darkColor,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            '1. Adayların sınav başlangıç saatinden en az 15 dakika önce sınav salonunda hazır bulunmaları gerekmektedir.\n'
                            '2. Sınava gelirken yanınızda T.C. Kimlik Kartı ve bu sınav giriş belgesini bulundurmanız zorunludur.\n'
                            '3. Cep telefonu, akıllı saat vb. her türlü elektronik cihazın sınav salonuna getirilmesi yasaktır.\n'
                            '4. Yanınızda kurşun kalem, silgi ve kalemtıraş bulundurunuz.',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 7.5,
                              color: greyColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'sinav_giris_belgeleri_A4_${widget.exam.id}.pdf',
      );
    } catch (e) {
      _showErrorSnackBar(e);
    }
  }

  static pw.Widget _buildA4SectionHeader(String title, PdfColor color, pw.Font fontBold) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        font: fontBold,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: color,
        letterSpacing: 1,
      ),
    );
  }

  static pw.Widget _buildA4InfoRow(String label, String value, pw.Font labelFont, pw.Font valueFont, {bool isHighlight = false, PdfColor? highlightColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: labelFont,
              fontSize: 7.5,
              color: PdfColors.grey500,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: valueFont,
              fontSize: 10,
              color: isHighlight && highlightColor != null ? highlightColor : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Loading Overlay ─────────────────────────────────────────────────────

  /// PDF oluştururken animasyonlu dialog göster, işlem bitince kapat
  Future<T> _withPdfLoadingOverlay<T>(Future<T> Function() work, {String? label}) async {
    String _currentLabel = label ?? 'PDF hazırlanıyor...';
    bool _overlayMounted = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // label değişimini dinleyebilmek için stream yerine basit pattern
          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated spinner
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const CircularProgressIndicator(
                            color: _primaryColor,
                            strokeWidth: 4,
                          ),
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: _primaryColor,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'PDF Oluşturuluyor',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label ?? 'Belgeler hazırlanıyor, lütfen bekleyiniz...',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    try {
      final result = await work();
      return result;
    } finally {
      if (_overlayMounted && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _overlayMounted = false;
    }
  }

  // ─── Font helpers (cached) ────────────────────────────────────────────────

  Future<pw.Font> _loadRegularFont() async {
    if (_cachedFont != null) return _cachedFont!;
    _cachedFont = await _loadRegularFontRaw();
    return _cachedFont!;
  }

  Future<pw.Font> _loadBoldFont() async {
    if (_cachedFontBold != null) return _cachedFontBold!;
    _cachedFontBold = await _loadBoldFontRaw();
    return _cachedFontBold!;
  }

  Future<pw.Font> _loadRegularFontRaw() async {
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

  Future<pw.Font> _loadBoldFontRaw() async {
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
