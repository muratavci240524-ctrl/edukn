import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/school/butterfly_exam_model.dart';
import '../models/school/seating_plan_model.dart';

/// Kelebek Sınav Sistemi PDF Servisi (Krokiler, Kapı Listeleri, Yoklama Listeleri, Genel Alfabetik Liste)
class ButterflyPdfService {
  /// Sınav başlığını kullanıcı tercihine göre döndürür
  static String _getExamTitle(ExamDistribution distribution) {
    if (!distribution.showExamTitleOnPdf) {
      return 'Deneme Sınavı';
    }
    return distribution.title.isNotEmpty ? distribution.title : 'Deneme Sınavı';
  }

  /// ===========================================================================
  /// 1. KAPI LİSTESİ PDF (SIRA NUMARASINA GÖRE SIRALI - A4 PORTRAIT)
  /// ===========================================================================
  static Future<Uint8List> generateGateListPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Koltuk / Sıra Numarasına Göre (1, 2, 3... 24) Sıralı Liste
    final occupiedSeats = room.seats.where((s) => s.student != null).toList();
    occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildGateListHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 12),
              _buildRoomInfoBanner(distribution, room, font, fontBold),
              pw.SizedBox(height: 10),
              _buildGateListTable(occupiedSeats, font, fontBold),
              pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
              _buildGateListFooter(distribution, occupiedSeats.length, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Kapı Listelerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllGateListsPdf({
    required ExamDistribution distribution,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final occupiedSeats = room.seats.where((s) => s.student != null).toList();
      occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildGateListHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 12),
                _buildRoomInfoBanner(distribution, room, font, fontBold),
                pw.SizedBox(height: 10),
                _buildGateListTable(occupiedSeats, font, fontBold),
                pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
                _buildGateListFooter(distribution, occupiedSeats.length, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// ===========================================================================
  /// 2. SALON SINAV YOKLAMA LİSTESİ (SIRA NUMARASINA GÖRE SIRALI - A4)
  /// ===========================================================================
  static Future<Uint8List> generateAttendanceListPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Koltuk / Sıra Numarasına Göre (1, 2, 3... 24) Sıralı Liste
    final occupiedSeats = room.seats.where((s) => s.student != null).toList();
    occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildAttendanceHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 12),
              _buildRoomInfoBanner(distribution, room, font, fontBold, isAttendance: true),
              pw.SizedBox(height: 10),
              _buildAttendanceTable(occupiedSeats, font, fontBold),
              pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
              _buildAttendanceFooter(distribution, room, occupiedSeats.length, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Yoklama Listelerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllAttendanceListsPdf({
    required ExamDistribution distribution,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final occupiedSeats = room.seats.where((s) => s.student != null).toList();
      occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildAttendanceHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 12),
                _buildRoomInfoBanner(distribution, room, font, fontBold, isAttendance: true),
                pw.SizedBox(height: 10),
                _buildAttendanceTable(occupiedSeats, font, fontBold),
                pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
                _buildAttendanceFooter(distribution, room, occupiedSeats.length, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// ===========================================================================
  /// 3. GENEL ALFABETİK ÖĞRENCİ YERLEŞİM LİSTESİ (TÜM OKUL / OTURUM - A-Z)
  /// ===========================================================================
  static Future<Uint8List> generateMasterAlphabeticalListPdf({
    required ExamDistribution distribution,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final List<Map<String, dynamic>> allSeated = [];

    for (final room in distribution.rooms) {
      for (final seat in room.seats) {
        if (seat.student != null) {
          allSeated.add({
            'student': seat.student!,
            'roomName': room.classroomName,
            'seatNumber': seat.seatNumber,
          });
        }
      }
    }

    allSeated.sort((a, b) {
      final sA = (a['student'] as ExamStudent).fullName.toLowerCase();
      final sB = (b['student'] as ExamStudent).fullName.toLowerCase();
      return sA.compareTo(sB);
    });

    const int itemsPerPage = 25; // A4 sayfasına taşmadan tam oturan güvenli satır sayısı
    final int totalPages = (allSeated.length / itemsPerPage).ceil().clamp(1, 999);

    for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
      final start = pageIdx * itemsPerPage;
      final end = (start + itemsPerPage).clamp(0, allSeated.length);
      final pageItems = allSeated.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildMasterHeader(distribution, font, fontBold, pageIdx + 1, totalPages),
                pw.SizedBox(height: 10),
                _buildMasterTable(pageItems, start, font, fontBold),
                pw.Spacer(),
                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 6),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Toplam Sınava Giren Öğrenci: ${allSeated.length}',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5),
                      ),
                      pw.Text(
                        'Sayfa ${pageIdx + 1} / $totalPages',
                        style: pw.TextStyle(font: font, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// ===========================================================================
  /// 4. GÖZETMEN SINAV KROKİSİ PDF (ÖĞRENCİ İMZASIZ - TEMİZ DÜZEN - A4)
  /// ===========================================================================
  static Future<Uint8List> generateSupervisorSeatingPlanPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final layout = room.layoutSnapshot;
    final isLandscape = layout.cols >= 4 || layout.rows <= 3;
    final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildSupervisorHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 8),
              _buildTeacherBoard(fontBold),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: _buildSupervisorGrid(room, font, fontBold),
              ),
              pw.SizedBox(height: 8),
              _buildSupervisorFooter(distribution, room, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Gözetmen Krokilerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllSupervisorPlansPdf({
    required ExamDistribution distribution,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final layout = room.layoutSnapshot;
      final isLandscape = layout.cols >= 4 || layout.rows <= 3;
      final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildSupervisorHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 8),
                _buildTeacherBoard(fontBold),
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: _buildSupervisorGrid(room, font, fontBold),
                ),
                pw.SizedBox(height: 8),
                _buildSupervisorFooter(distribution, room, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // ===========================================================================
  // WIDGET BİLEŞENLERİ: KAPI LİSTESİ & YOKLAMA LİSTESİ
  // ===========================================================================

  static pw.Widget _buildGateListHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                distribution.schoolTypeName.toUpperCase(),
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.indigo200),
              ),
              pw.Text(
                examTitle,
                style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName}',
                style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.indigo100),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'KAPI LİSTESİ',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$dateStr • ${distribution.examTime}',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAttendanceHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                distribution.schoolTypeName.toUpperCase(),
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.blueGrey200),
              ),
              pw.Text(
                examTitle,
                style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName}',
                style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.blueGrey100),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.amber400,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'SALON YOKLAMA LİSTESİ',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.black),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$dateStr • ${distribution.examTime}',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMasterHeader(
    ExamDistribution distribution,
    pw.Font font,
    pw.Font fontBold,
    int currentPage,
    int totalPages,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${distribution.schoolTypeName.toUpperCase()} • $examTitle',
                style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.white),
              ),
              pw.Text(
                'GENEL ÖĞRENCİ ALFABETİK YERLEŞİM LİSTESİ (A - Z)',
                style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.amber300),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName} • Tarih: $dateStr • Saat: ${distribution.examTime}',
                style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.indigo100),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'Sayfa $currentPage / $totalPages',
              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRoomInfoBanner(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold, {
    bool isAttendance = false,
  }) {
    final hasCustomSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text('SINAV SALONU: ', style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey800)),
              pw.Text(room.classroomName, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.indigo900)),
            ],
          ),
          if (hasCustomSupervisor)
            pw.Row(
              children: [
                pw.Text('GÖZETMEN: ', style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.grey800)),
                pw.Text(room.supervisorName!, style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.black)),
              ],
            ),
          pw.Row(
            children: [
              pw.Text('TOPLAM ÖĞRENCİ: ', style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.grey800)),
              pw.Text('${room.seatedStudentCount} Öğrenci', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900)),
            ],
          ),
        ],
      ),
    );
  }

  /// Kapı Listesi Tablosu (Sıra Numarasına Göre 1, 2, 3... Sıralı)
  static pw.Widget _buildGateListTable(
    List<SeatCoordinate> seats,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(3.8),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableHeaderCell('SIRA NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
          ],
        ),
        ...seats.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final seat = entry.value;
          final s = seat.student!;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('${seat.seatNumber}', fontBold, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    );
  }

  /// Yoklama Listesi Tablosu (Sıra Numarasına Göre 1, 2, 3... Sıralı)
  static pw.Widget _buildAttendanceTable(
    List<SeatCoordinate> seats,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(3.5),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.5),
        5: pw.FlexColumnWidth(1.8),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          children: [
            _buildTableHeaderCell('SIRA NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
            _buildTableHeaderCell('KATILIM (+/-)', fontBold),
            _buildTableHeaderCell('İMZA', fontBold),
          ],
        ),
        ...seats.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final seat = entry.value;
          final s = seat.student!;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('${seat.seatNumber}', fontBold, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
              _buildTableCell('[   ]', font, align: pw.TextAlign.center),
              _buildTableCell('', font),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildMasterTable(
    List<Map<String, dynamic>> items,
    int startIndex,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.8),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(3.8),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(2.5),
        5: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.indigo100),
          children: [
            _buildTableHeaderCell('SIRA', fontBold),
            _buildTableHeaderCell('NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
            _buildTableHeaderCell('SINAV SALONU', fontBold),
            _buildTableHeaderCell('SIRA NO', fontBold),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = startIndex + entry.key + 1;
          final item = entry.value;
          final s = item['student'] as ExamStudent;
          final roomName = item['roomName'] as String;
          final seatNo = item['seatNumber'] as int;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('$idx', font, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
              _buildTableCell(roomName, fontBold, align: pw.TextAlign.center),
              _buildTableCell('$seatNo', fontBold, align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeaderCell(String text, pw.Font fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    pw.Font font, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.2, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _buildGateListFooter(
    ExamDistribution distribution,
    int studentCount,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final nowStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '• Sınav salonuna giriş yaparken lütfen sıranıza oturun ve kimliğinizi masada bulundurun.',
            style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700),
          ),
          pw.Text(
            'Oluşturulma: $nowStr',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAttendanceFooter(
    ExamDistribution distribution,
    ExamRoom room,
    int studentCount,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final hasSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    final supervisorText = hasSupervisor
        ? 'Gözetmen: ${room.supervisorName!.trim()}'
        : 'Gözetmen: _____________________________';

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Katılan Öğrenci Sayısı: [ ____ ]', style: pw.TextStyle(font: fontBold, fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text('Katılmayan Öğrenci Sayısı: [ ____ ]', style: pw.TextStyle(font: fontBold, fontSize: 9)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(supervisorText, style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900)),
              pw.SizedBox(height: 6),
              pw.Text('İmza: _____________________________', style: pw.TextStyle(font: font, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET BİLEŞENLERİ: GÖZETMEN KROKİSİ
  // ===========================================================================

  static pw.Widget _buildSupervisorHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${distribution.schoolTypeName.toUpperCase()} • $examTitle',
                style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.white),
              ),
              pw.Text(
                'SALON OTURMA KROKİSİ: ${room.classroomName}',
                style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.amber300),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName} • Tarih: $dateStr • Saat: ${distribution.examTime}',
                style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.indigo100),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              '${room.seatedStudentCount} Öğrenci / ${room.totalCapacity} Kapasite',
              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTeacherBoard(pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      alignment: pw.Alignment.center,
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey800,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        '• ÖĞRETMEN KÜRSÜSÜ / YAZI TAHTASI •',
        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _buildSupervisorGrid(
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final layout = room.layoutSnapshot;
    final Map<String, SeatCoordinate> seatMap = {
      for (final s in room.seats) '${s.row}-${s.col}-${s.slotIndex}': s,
    };

    return pw.Column(
      children: List.generate(layout.rows, (r) {
        return pw.Expanded(
          child: pw.Row(
            children: List.generate(layout.cols, (c) {
              final cell = layout.cells.firstWhere(
                (cl) => cl.row == r && cl.col == c,
                orElse: () => DeskCell(
                  row: r,
                  col: c,
                  cellType: CellType.aisle,
                  deskType: DeskType.single,
                ),
              );

              return pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2.5),
                  child: _buildLayoutCellWidget(cell, seatMap, font, fontBold),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  static pw.Widget _buildLayoutCellWidget(
    DeskCell cell,
    Map<String, SeatCoordinate> seatMap,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (cell.cellType == CellType.aisle) {
      return pw.Center(
        child: pw.Text(
          'KORİDOR',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400),
        ),
      );
    }

    if (cell.cellType != CellType.desk) {
      return pw.SizedBox();
    }

    if (cell.deskType == DeskType.single) {
      final seat = seatMap['${cell.row}-${cell.col}-0'];
      return _buildSeatBox(seat, font, fontBold);
    } else if (cell.deskType == DeskType.double) {
      final seatLeft = seatMap['${cell.row}-${cell.col}-0'];
      final seatRight = seatMap['${cell.row}-${cell.col}-1'];

      return pw.Row(
        children: [
          pw.Expanded(child: _buildSeatBox(seatLeft, font, fontBold)),
          pw.SizedBox(width: 3),
          pw.Expanded(child: _buildSeatBox(seatRight, font, fontBold)),
        ],
      );
    }

    return pw.SizedBox();
  }

  static pw.Widget _buildSeatBox(
    SeatCoordinate? seat,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (seat == null) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
          color: PdfColors.grey100,
        ),
      );
    }

    final s = seat.student;
    final isOccupied = s != null;

    return pw.Container(
      padding: const pw.EdgeInsets.all(3),
      decoration: pw.BoxDecoration(
        color: isOccupied ? PdfColors.white : PdfColors.grey100,
        border: pw.Border.all(
          color: isOccupied ? PdfColors.indigo800 : PdfColors.grey300,
          width: isOccupied ? 0.9 : 0.5,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: isOccupied
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.indigo900,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                      child: pw.Text(
                        'No: ${seat.seatNumber}',
                        style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: PdfColors.white),
                      ),
                    ),
                    pw.Text(
                      s.className,
                      style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.indigo900),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  s.fullName,
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.black),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'No: ${s.studentNumber}',
                      style: pw.TextStyle(font: font, fontSize: 6.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            )
          : pw.Center(
              child: pw.Text(
                'No: ${seat.seatNumber}\n[ BOŞ ]',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: 6.5, color: PdfColors.grey500),
              ),
            ),
    );
  }

  static pw.Widget _buildSupervisorFooter(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final nowStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    final hasSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    final supervisorText = hasSupervisor
        ? 'Gözetmen: ${room.supervisorName!.trim()}'
        : 'Gözetmen: _____________________________';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '• Öğrencilerin krokide belirtilen masalara oturmalarını kontrol ediniz.',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            supervisorText,
            style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.indigo900),
          ),
          pw.Text(
            'Tarih: $nowStr',
            style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }
}
