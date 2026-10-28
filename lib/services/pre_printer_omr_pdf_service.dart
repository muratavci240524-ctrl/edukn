import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/optical_form_template.dart';

/// Öğrenci verisi (adı, soyadı, okul numarası).
class OmrStudent {
  final String firstName;
  final String lastName;
  final String studentNumber;
  final String tcNo;

  const OmrStudent({
    required this.firstName,
    required this.lastName,
    required this.studentNumber,
    this.tcNo = '',
  });
}

/// Parametrik Optik Form Ön Kodlayıcı PDF Servisi.
///
/// Her öğrenci için bağımsız bir PDF sayfası üretir.
/// Sayfaya HİÇBİR arka plan, çizgi veya çerçeve çizilmez —
/// sadece ilgili koordinatlara siyah dolu daireler ve küçük bilgi metni eklenir.
///
/// Koordinat sistemi:
/// - Şablon koordinatları: kağıdın sol üst köşesinden mm cinsinden.
/// - PDF canvas (PdfGraphics): sol alt köşe (0,0), y yukarı artar.
/// - Dönüşüm: canvas_x = xMm * mm2pt, canvas_y = pageHeightPt - yMm * mm2pt
class PrePrinterOmrPdfService {
  // ── Sabitler ──────────────────────────────────────────────────────────────

  /// 1 mm = 2.8346 PDF point
  static const double mm2pt = 2.8346;

  /// 29 harfli Türk alfabesi (optik form sırası)
  static const List<String> _trAlphabet = [
    'A','B','C','Ç','D','E','F','G','Ğ','H',
    'I','İ','J','K','L','M','N','O','Ö','P',
    'R','S','Ş','T','U','Ü','V','Y','Z',
  ];

  /// Rakam satırları (okul numarası için)
  static const List<String> _digits = [
    '0','1','2','3','4','5','6','7','8','9',
  ];

  // ── Ana Fonksiyon ─────────────────────────────────────────────────────────

  /// Öğrenciler için tek PDF dosyası üretir.
  ///
  /// [students]    : Baskı alınacak öğrenci listesi.
  /// [template]    : Optik form koordinat şablonu.
  /// [calibration] : Yazıcı kayma ofseti.
  /// [className]   : Bilgi amaçlı sınıf/şube adı.
  static Future<Uint8List> generatePrePrintedOmrPdf({
    required List<OmrStudent> students,
    required OpticalFormTemplate template,
    required PrinterCalibration calibration,
    String className = '',
  }) async {
    final pdf = pw.Document();

    // Küçük bilgi metni için font
    final font = await PdfGoogleFonts.notoSansRegular();

    final pageFormat = PdfPageFormat(
      template.paperWidthMm * mm2pt,
      template.paperHeightMm * mm2pt,
      marginAll: 0,
    );

    for (final student in students) {
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (ctx) => _buildPage(
            student: student,
            template: template,
            calibration: calibration,
            font: font,
            pageWidthPt: template.paperWidthMm * mm2pt,
            pageHeightPt: template.paperHeightMm * mm2pt,
            className: className,
          ),
        ),
      );
    }

    return pdf.save();
  }

  // ── Sayfa Oluşturucu ──────────────────────────────────────────────────────

  static pw.Widget _buildPage({
    required OmrStudent student,
    required OpticalFormTemplate template,
    required PrinterCalibration calibration,
    required pw.Font font,
    required double pageWidthPt,
    required double pageHeightPt,
    required String className,
  }) {
    // Küçük bilgi satırı (sol üst köşe, 2mm içeri)
    final infoText =
        '${student.firstName} ${student.lastName}  •  No: ${student.studentNumber}'
        '${student.tcNo.isNotEmpty ? '  •  TC: ${student.tcNo}' : ''}'
        '${className.isNotEmpty ? '  •  $className' : ''}';

    return pw.Stack(
      children: [
        // ── Küçük bilgi metni (sol üst, gri, baskıyı bozmaz) ──────────────
        pw.Positioned(
          left: 4,
          top: 3,
          child: pw.Text(
            infoText,
            style: pw.TextStyle(
              font: font,
              fontSize: 6,
              color: PdfColors.grey600,
            ),
          ),
        ),

        // ── Tüm dolu daireler — tek CustomPaint ───────────────────────────
        pw.Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          child: pw.CustomPaint(
            painter: (canvas, size) => _drawAllCircles(
              canvas: canvas,
              size: size,
              student: student,
              template: template,
              calibration: calibration,
            ),
          ),
        ),
      ],
    );
  }

  // ── Daire Çizici ──────────────────────────────────────────────────────────

  static void _drawAllCircles({
    required PdfGraphics canvas,
    required PdfPoint size,
    required OmrStudent student,
    required OpticalFormTemplate template,
    required PrinterCalibration calibration,
  }) {
    final calX = calibration.offsetXMm;
    final calY = calibration.offsetYMm;
    final r = (template.circleDiameterMm / 2) * mm2pt;

    // Ad harfleri
    _drawFieldCircles(
      canvas: canvas,
      pageHeightPt: size.y,
      chars: _toOpticalChars(student.firstName),
      alphabet: _trAlphabet,
      field: template.nameField,
      r: r,
      calXMm: calX,
      calYMm: calY,
    );

    // Soyad harfleri
    _drawFieldCircles(
      canvas: canvas,
      pageHeightPt: size.y,
      chars: _toOpticalChars(student.lastName),
      alphabet: _trAlphabet,
      field: template.surnameField,
      r: r,
      calXMm: calX,
      calYMm: calY,
    );

    // Okul numarası rakamları
    _drawFieldCircles(
      canvas: canvas,
      pageHeightPt: size.y,
      chars: student.studentNumber.replaceAll(' ', '').split(''),
      alphabet: _digits,
      field: template.noField,
      r: r,
      calXMm: calX,
      calYMm: calY,
    );

    // T.C. Kimlik No rakamları
    if (student.tcNo.isNotEmpty) {
      _drawFieldCircles(
        canvas: canvas,
        pageHeightPt: size.y,
        chars: student.tcNo.replaceAll(' ', '').split(''),
        alphabet: _digits,
        field: template.tcField,
        r: r,
        calXMm: calX,
        calYMm: calY,
      );
    }
  }

  /// Bir alan (ad/soyad/no) için dolu daireleri çizer.
  ///
  /// Her sütun = bir karakter konumu.
  /// Her satır = alfabedeki bir harf ya da rakam.
  /// Sadece öğrencinin karakterine karşılık gelen satırda daire çizilir.
  static void _drawFieldCircles({
    required PdfGraphics canvas,
    required double pageHeightPt,
    required List<String> chars,
    required List<String> alphabet,
    required FieldTemplate field,
    required double r,
    required double calXMm,
    required double calYMm,
  }) {
    final colCount = chars.length.clamp(0, field.maxCols);

    for (int col = 0; col < colCount; col++) {
      final targetChar = chars[col];
      final rowIndex = alphabet.indexOf(targetChar);
      if (rowIndex < 0) continue; // Alfabede yoksa atla

      // Kağıt üzerindeki merkez koordinatı (mm, sol üst köşe referanslı)
      final centerXMm = field.startXMm + col * field.colSpacingMm + calXMm;
      final centerYMm = field.startYMm + rowIndex * field.rowSpacingMm + calYMm;

      // PDF canvas koordinatına dönüştür (sol alt köşe referanslı)
      final cx = centerXMm * mm2pt;
      final cy = pageHeightPt - centerYMm * mm2pt;

      // Sayfa sınırı kontrolü (taşma güvenliği)
      if (cx - r < 0 || cx + r > pageHeightPt * 2 || cy - r < 0 || cy > pageHeightPt) {
        continue;
      }

      canvas
        ..setFillColor(PdfColors.black)
        ..drawEllipse(cx - r, cy - r, r * 2, r * 2)
        ..fillPath();
    }
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────

  /// Türkçe karakterleri büyük harfe çevirerek optik alfabeye uyumlu hale getirir.
  /// Boşluklar ve bilinmeyen karakterler çıkarılır.
  static List<String> _toOpticalChars(String text) {
    return text
        .toUpperCase()
        .replaceAll('Ç', 'Ç')
        .replaceAll('Ğ', 'Ğ')
        .replaceAll('İ', 'İ')
        .replaceAll('Ö', 'Ö')
        .replaceAll('Ş', 'Ş')
        .replaceAll('Ü', 'Ü')
        // ASCII I → Türkçe İ (büyük harf İ)
        .split('')
        .where((c) => _trAlphabet.contains(c))
        .toList();
  }
}
