import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/school/seating_plan_model.dart';

class SeatingPdfService {
  /// Sınıf Oturma Planı PDF Dokümanı Üretir
  static Future<Uint8List> generateSeatingPlanPdf({
    required SeatingPlan plan,
    String? schoolLogoUrl,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Satır ve sütun sayılarını belirle
    int maxRow = 0;
    int maxCol = 0;
    for (var cell in plan.cells) {
      if (cell.row > maxRow) maxRow = cell.row;
      if (cell.col > maxCol) maxCol = cell.col;
    }
    final rowsCount = maxRow + 1;
    final colsCount = maxCol + 1;

    final isLandscape = colsCount >= 4 || rowsCount <= 4;
    final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(plan, font, fontBold),
              pw.SizedBox(height: 10),

              // Teacher Desk / Board Banner
              _buildTeacherBoard(fontBold),
              pw.SizedBox(height: 12),

              // Seating Grid
              pw.Expanded(
                child: _buildGrid(plan, rowsCount, colsCount, font, fontBold),
              ),
              pw.SizedBox(height: 8),

              // Footer Info
              _buildFooter(plan, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(SeatingPlan plan, pw.Font font, pw.Font fontBold) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'SINIF OTURMA PLANI',
                style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.blueGrey900),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                plan.title,
                style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.blueGrey700),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo50,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'Şube: ${plan.className}',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.indigo900),
                    ),
                  ),
                  if (plan.classroomName != null && plan.classroomName!.isNotEmpty) ...[
                    pw.SizedBox(width: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'Derslik: ${plan.classroomName}',
                        style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey800),
                      ),
                    ),
                  ],
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Tarih: ${dateFormat.format(plan.planDate)}',
                style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTeacherBoard(pw.Font fontBold) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey800,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Center(
        child: pw.Text(
          'TAHTA / ÖĞRETMEN KÜRSÜSÜ',
          style: pw.TextStyle(
            font: fontBold,
            fontSize: 10,
            color: PdfColors.white,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildGrid(
    SeatingPlan plan,
    int rowsCount,
    int colsCount,
    pw.Font font,
    pw.Font fontBold,
  ) {
    // Koordinatlara göre indexle
    final Map<String, DeskCell> cellMap = {};
    for (var c in plan.cells) {
      cellMap['${c.row}-${c.col}'] = c;
    }

    return pw.Column(
      children: List.generate(rowsCount, (r) {
        return pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              children: List.generate(colsCount, (c) {
                final cell = cellMap['$r-$c'];

                if (cell == null || cell.isAisle) {
                  // Koridor
                  return pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                      child: pw.Center(
                        child: pw.Text(
                          '· · ·',
                          style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey300),
                        ),
                      ),
                    ),
                  );
                }

                // Masa Hücresi
                return pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // Masa Başlığı
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              cell.customLabel ?? 'Masa ${r + 1}-${c + 1}',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 7.5,
                                color: PdfColors.blueGrey800,
                              ),
                            ),
                          ],
                        ),
                        pw.Divider(color: PdfColors.grey200, thickness: 0.5, height: 4),

                        // Koltuklar
                        pw.Expanded(
                          child: pw.Row(
                            children: cell.slots.map((slot) {
                              return pw.Expanded(
                                child: pw.Container(
                                  margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: slot.isOccupied
                                        ? (slot.isPinned ? PdfColors.amber50 : PdfColors.white)
                                        : PdfColors.grey100,
                                    borderRadius: pw.BorderRadius.circular(4),
                                    border: pw.Border.all(
                                      color: slot.isOccupied
                                          ? (slot.isPinned ? PdfColors.amber300 : PdfColors.blue100)
                                          : PdfColors.grey200,
                                      width: 0.6,
                                    ),
                                  ),
                                  child: slot.isOccupied
                                      ? pw.Column(
                                          mainAxisAlignment: pw.MainAxisAlignment.center,
                                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                                          children: [
                                            if (slot.studentNumber != null &&
                                                slot.studentNumber!.isNotEmpty)
                                              pw.Text(
                                                '#${slot.studentNumber}',
                                                style: pw.TextStyle(
                                                  font: fontBold,
                                                  fontSize: 6.5,
                                                  color: PdfColors.indigo700,
                                                ),
                                              ),
                                            pw.Text(
                                              slot.studentName ?? '',
                                              textAlign: pw.TextAlign.center,
                                              maxLines: 2,
                                              style: pw.TextStyle(
                                                font: fontBold,
                                                fontSize: 8,
                                                color: PdfColors.grey900,
                                              ),
                                            ),
                                            if (slot.isPinned)
                                              pw.Text(
                                                '[Sabit]',
                                                style: pw.TextStyle(
                                                  font: font,
                                                  fontSize: 6,
                                                  color: PdfColors.amber800,
                                                ),
                                              ),
                                          ],
                                        )
                                      : pw.Center(
                                          child: pw.Text(
                                            'Boş',
                                            style: pw.TextStyle(
                                              font: font,
                                              fontSize: 7,
                                              color: PdfColors.grey400,
                                            ),
                                          ),
                                        ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      }),
    );
  }

  static pw.Widget _buildFooter(SeatingPlan plan, pw.Font font, pw.Font fontBold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Toplam Oturan: ${plan.assignedStudentCount} Öğrenci  |  Sabitlenen: ${plan.pinnedStudentCount}',
          style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey600),
        ),
        pw.Text(
          'eduKN Akıllı Oturma Planı Sistemi',
          style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.indigo600),
        ),
      ],
    );
  }
}
