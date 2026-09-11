import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/school/student_grouping_model.dart';

class StudentGroupingPdfService {
  /// Grup Çalışması PDF Raporu Üretir
  static Future<Uint8List> generateGroupingPlanPdf({
    required GroupingPlanModel plan,
    String? schoolTypeName,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final isLandscape = plan.groups.length >= 4;
    final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
    final dateFormat = DateFormat('dd.MM.yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          return [
            // Üst Başlık & Okul Bilgisi
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.indigo200),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        plan.title,
                        style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.indigo900),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        '${plan.className} Şubesi • ${plan.mode.title}',
                        style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Tarih: ${dateFormat.format(plan.createdAt)}',
                        style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.grey800),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Toplam ${plan.totalStudents} Öğrenci • ${plan.groups.length} Grup',
                        style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Gruplar Grid/Wrap Formatında
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: plan.groups.map((group) {
                final groupWidth = isLandscape ? 230.0 : 250.0;
                final pdfColor = PdfColor.fromInt(group.groupColor.value);

                return pw.Container(
                  width: groupWidth,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: pdfColor, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Grup Başlığı
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: pw.BoxDecoration(
                          color: pdfColor,
                          borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(6.5)),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              group.groupName,
                              style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.white),
                            ),
                            pw.Text(
                              '${group.totalStudents} Öğrenci (Ort: ${group.averageScore.toStringAsFixed(1)})',
                              style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.white),
                            ),
                          ],
                        ),
                      ),

                      // Öğrenci Listesi
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Column(
                          children: group.students.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final student = entry.value;

                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: pw.BoxDecoration(
                                color: idx % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.Text(
                                    '${idx + 1}.',
                                    style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey700),
                                  ),
                                  pw.SizedBox(width: 6),
                                  pw.Expanded(
                                    child: pw.Text(
                                      student.name,
                                      style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.grey900),
                                    ),
                                  ),
                                  if (student.studentNumber != null)
                                    pw.Text(
                                      '#${student.studentNumber}',
                                      style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
                                    ),
                                  if (plan.mode != GroupingMode.random) ...[
                                    pw.SizedBox(width: 6),
                                    pw.Text(
                                      '${student.academicScore.toStringAsFixed(0)}p',
                                      style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.indigo700),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
