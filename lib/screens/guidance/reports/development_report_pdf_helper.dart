import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../../models/guidance/development_report/development_report_model.dart';

class DevelopmentReportPdfHelper {
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF3F51B5); // Indigo
  static const PdfColor secondaryColor = PdfColor.fromInt(
    0xFFE8EAF6,
  ); // Soft Indigo
  static const PdfColor accentColor = PdfColor.fromInt(
    0xFFFF5252,
  ); // Red for risks

  static Future<void> generateAndPrint(
    DevelopmentReport report,
    String targetName, {
    String? institutionName,
  }) async {
    final pdf = pw.Document();

    // Use Google Fonts for Turkish character support
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
          italic: fontItalic,
        ),
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            _buildPremiumHeader(report, targetName, institutionName),
            pw.SizedBox(height: 24),
            _buildScoreGrid(report),
            pw.SizedBox(height: 32),
            _buildAnalysisSection(report),
            pw.Spacer(),
            _buildPremiumFooter(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Rapor_${targetName.replaceAll(' ', '_')}.pdf',
    );
  }

  static Future<void> generateBulkPdf(
    List<DevelopmentReport> reports,
    Map<String, String> targetNames, {
    String? institutionName,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    for (var report in reports) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
            italic: fontItalic,
          ),
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              _buildPremiumHeader(
                report,
                targetNames[report.targetId] ?? "Bilinmiyor",
                institutionName,
              ),
              pw.SizedBox(height: 24),
              _buildScoreGrid(report),
              pw.SizedBox(height: 32),
              _buildAnalysisSection(report),
              pw.Spacer(),
              _buildPremiumFooter(),
            ];
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Toplu_Raporlar.pdf',
    );
  }

  static pw.Widget _buildPremiumHeader(
    DevelopmentReport report,
    String name,
    String? institution,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "360° GELİŞİM ANALİZİ",
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  institution ?? "Eğitim Kurumu Raporu",
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: secondaryColor,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                report.term.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Divider(color: primaryColor, thickness: 1.5),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            _buildHeaderInfoItem("Kişi", name),
            pw.SizedBox(width: 40),
            _buildHeaderInfoItem(
              "Hedef Kitle",
              _formatTargetType(report.targetType),
            ),
            pw.SizedBox(width: 40),
            _buildHeaderInfoItem(
              "Tarih",
              DateFormat('dd.MM.yyyy').format(report.createdAt),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
      ],
    );
  }

  static pw.Widget _buildHeaderInfoItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey600,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _buildScoreGrid(DevelopmentReport report) {
    final scores = report.categoryScores;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          "PERFORMANS VE GELİŞİM SKORLARI",
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Wrap(
          spacing: 20,
          runSpacing: 20,
          children: scores.entries.map((entry) {
            return pw.Container(
              width: 230,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey200),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    entry.key,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Stack(
                          children: [
                            pw.Container(
                              height: 8,
                              decoration: pw.BoxDecoration(
                                color: PdfColors.grey200,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                            ),
                            pw.Container(
                              height: 8,
                              width:
                                  (entry.value / 5.0) *
                                  200, // Normalized to 5.0
                              decoration: pw.BoxDecoration(
                                color: primaryColor,
                                borderRadius: pw.BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        entry.value.toStringAsFixed(1),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  static pw.Widget _buildAnalysisSection(DevelopmentReport report) {
    final summary =
        report.analysis['summary'] ??
        'Henüz detaylı analiz girişi yapılmamıştır.';
    final risks = report.analysis['riskFactors'] as List?;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: secondaryColor, // Lighter version or just the solid color
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "GENEL DEĞERLENDİRME ÖZETİ",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                summary.toString(),
                style: pw.TextStyle(fontSize: 11, color: PdfColors.black),
              ),
            ],
          ),
        ),
        if (risks != null && risks.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Text(
            "RİSK FAKTÖRLERİ VE ÖNERİLER",
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: accentColor,
            ),
          ),
          pw.SizedBox(height: 8),
          ...risks.map(
            (r) => pw.Bullet(
              text: r.toString(),
              style: pw.TextStyle(fontSize: 11, color: PdfColors.red900),
              bulletColor: accentColor,
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _buildPremiumFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            _buildSignatureBlock("İlgili Birim / Öğretmen"),
            _buildSignatureBlock("Rehberlik Servisi"),
            _buildSignatureBlock("Okul Yönetimi"),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          "Bu rapor eduKN modülü tarafından otomatik olarak oluşturulmuştur. @ ${DateTime.now().year}",
          style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ],
    );
  }

  static pw.Widget _buildSignatureBlock(String title) {
    return pw.Column(
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 40),
        pw.Container(width: 120, height: 0.5, color: PdfColors.grey),
        pw.SizedBox(height: 4),
        pw.Text(
          "Ad Soyad / İmza",
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
    );
  }

  static String _formatTargetType(String type) {
    switch (type) {
      case 'student':
        return 'Öğrenci';
      case 'teacher':
        return 'Öğretmen';
      case 'personnel':
        return 'Personel';
      default:
        return type;
    }
  }
}
