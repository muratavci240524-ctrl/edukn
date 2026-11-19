import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/assessment/external_exam_model.dart';
import '../models/assessment/external_exam_result_model.dart';

/// Dış katılımlı sınav karnesini PDF olarak üretir / yazdırır (tek kişi veya toplu).
class ExternalExamKarnePdfService {
  static pw.Font? _font;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    _font ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  }

  static PdfColor _c(int rgb) => PdfColor.fromInt(0xFF000000 | rgb);

  static List<PdfColor> _bursColors(int rate) {
    if (rate >= 100) return [_c(0xF59E0B), _c(0xEA580C)];
    if (rate >= 75) return [_c(0x059669), _c(0x34D399)];
    if (rate >= 50) return [_c(0x0891B2), _c(0x22D3EE)];
    return [_c(0x6D28D9), _c(0xA78BFA)];
  }

  static Future<pw.Document> build({
    required ExternalExam exam,
    required List<ExternalExamResult> results,
    String? schoolName,
  }) async {
    await _loadFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _font!, bold: _bold!),
    );
    for (final r in results) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => _page(exam, r, schoolName),
        ),
      );
    }
    return doc;
  }

  static pw.Widget _page(ExternalExam exam, ExternalExamResult r, String? school) {
    final navy = _c(0x1E3A8A);
    pw.Widget cell(String t, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.center}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: pw.Text(
            t,
            textAlign: align,
            style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.grey900),
          ),
        );

    pw.Widget stat(String label, String value, PdfColor c) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: c, width: 1),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: c)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ]),
      ),
    );

    final masked = r.maskedTc;
return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(12)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if ((school ?? '').isNotEmpty)
              pw.Text(school!.toUpperCase(), style: pw.TextStyle(fontSize: 10, color: PdfColors.grey300, fontWeight: pw.FontWeight.bold)),
            pw.Text(exam.title, style: pw.TextStyle(fontSize: 18, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            pw.Text('SINAV KARNESİ', style: pw.TextStyle(fontSize: 10, color: _c(0xFDE68A), fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _c(0xF8FAFC), border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('ADAY', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text(r.fullName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('T.C. KİMLİK NO', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text(masked, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ])),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SINIF', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text('${r.gradeLevel}. Sınıf', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('OKUDUĞU OKUL', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text(r.currentSchool.isEmpty ? '-' : r.currentSchool, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ])),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          stat('PUAN', r.score.toStringAsFixed(2), navy),
          stat('SIRALAMA  (/${r.totalInGrade})', '${r.rank}', _c(0xEA580C)),
          stat('TOPLAM NET', r.net.toStringAsFixed(2), _c(0x059669)),
        ]),
        pw.SizedBox(height: 16),
        pw.Table(
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.6)),
          columnWidths: {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1), 4: pw.FlexColumnWidth(1.2)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              cell('DERS', bold: true, align: pw.TextAlign.left), cell('D', bold: true), cell('Y', bold: true), cell('B', bold: true), cell('NET', bold: true),
            ]),
            for (final s in r.orderedSubjects)
              pw.TableRow(children: [
                cell(s.name, align: pw.TextAlign.left),
                cell('${s.correct}', color: _c(0x059669)),
                cell('${s.wrong}', color: _c(0xDC2626)),
                cell('${s.empty}'),
                cell(s.net.toStringAsFixed(2), bold: true),
              ]),
            pw.TableRow(decoration: pw.BoxDecoration(color: _c(0xE0E7FF)), children: [
              cell('TOPLAM', bold: true, align: pw.TextAlign.left),
              cell('${r.correct}', bold: true, color: _c(0x059669)),
              cell('${r.wrong}', bold: true, color: _c(0xDC2626)),
              cell('${r.empty}', bold: true),
              cell(r.net.toStringAsFixed(2), bold: true),
            ]),
          ],
        ),
        pw.SizedBox(height: 18),
        if (exam.scholarshipEnabled)
          r.scholarshipRate > 0
              ? pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    gradient: pw.LinearGradient(colors: _bursColors(r.scholarshipRate)),
                    borderRadius: pw.BorderRadius.circular(14),
                  ),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('TEBRİKLER!', style: pw.TextStyle(fontSize: 10, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('%${r.scholarshipRate} Burs Kazandınız', style: pw.TextStyle(fontSize: 20, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${r.gradeLevel}. sınıf sıralamanız ${r.rank}. olduğu için %${r.scholarshipRate} burs hakkı kazandınız. Kayıt işlemleri için kurumumuzla iletişime geçiniz.',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
                    ),
                  ]),
                )
              : pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(color: _c(0xF1F5F9), border: pw.Border.all(color: _c(0xCBD5E1)), borderRadius: pw.BorderRadius.circular(10)),
                  child: pw.Text('Bu sınavda burs kazanma sıralamasına girilemedi. Sınava katıldığınız için teşekkür ederiz.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey700)),
                ),
        pw.Spacer(),
        pw.Text(
          'Sıralama ${r.gradeLevel}. sınıf seviyesindeki ${r.totalInGrade} aday arasında hesaplanmıştır.',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  /// Tarayıcıda / cihazda yazdırma-PDF penceresini açar.
  static Future<void> printKarneler({
    required ExternalExam exam,
    required List<ExternalExamResult> results,
    String? schoolName,
  }) async {
    final doc = await build(exam: exam, results: results, schoolName: schoolName);
    await Printing.layoutPdf(
      name: '${exam.title} - Karne',
      onLayout: (_) async => doc.save(),
    );
  }
}
