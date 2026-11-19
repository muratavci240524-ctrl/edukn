import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/school/butterfly_exam_model.dart';
import 'butterfly_supervisor_table_data.dart';

/// Gözetmen çizelgesini (salon x oturum/devre) yatay A4 üzerinde geniş ve şık bir PDF olarak üretir.
class ButterflySupervisorTablePdf {
  static const double _margin = 22;
  static const double _roomW = 66;
  static const double _gapW = 8;

  static Future<Uint8List> generate(ExamDistribution exam) async {
    final data = SupervisorTableData.from(exam);
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();

    final format = PdfPageFormat.a4.landscape;
    final contentW = format.width - _margin * 2;
    final sessions = data.sessions;
    final rooms = data.rooms;

    final totalCols = data.totalColumns < 1 ? 1 : data.totalColumns;
    final gaps = (sessions.length - 1) * _gapW;
    final unit = (contentW - _roomW - gaps) / totalCols;

    final dateStr = DateFormat('dd.MM.yyyy').format(exam.examDate);
    final printedAt = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    // Satır yüksekliği ve sayfa başına satır sayısı
    final bool roomy = rooms.length <= 12;
    final double rowH = roomy ? 32 : 24;
    final double nameFont = roomy ? 9.5 : 8.3;
    final int firstPageRows = roomy ? 12 : 16;
    final int nextPageRows = roomy ? 15 : 20;

    final List<List<ExamRoom>> chunks = [];
    if (rooms.isEmpty) {
      chunks.add([]);
    } else {
      int i = 0;
      bool first = true;
      while (i < rooms.length) {
        final take = first ? firstPageRows : nextPageRows;
        chunks.add(rooms.sublist(i, (i + take).clamp(0, rooms.length)));
        i += take;
        first = false;
      }
    }

    pw.Widget banner() {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(colors: [PdfColors.indigo900, PdfColors.indigo700]),
          borderRadius: pw.BorderRadius.circular(9),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'GÖZETMEN ÇİZELGESİ',
                    style: pw.TextStyle(font: bold, fontSize: 9.5, color: PdfColors.indigo100),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    exam.title,
                    style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColors.white),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${exam.lessonName} • ${exam.schoolTypeName}',
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.indigo100),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(7),
              ),
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  _infoItem('Sınav Tarihi', dateStr, font, bold),
                  pw.SizedBox(width: 16),
                  _infoItem('Sınav Saati', exam.examTime, font, bold),
                  pw.SizedBox(width: 16),
                  _infoItem('Salon Sayısı', '${rooms.length} Salon', font, bold),
                ],
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget headerRows() {
      final List<pw.Widget> top = [];
      final List<pw.Widget> bottom = [];
      for (int si = 0; si < sessions.length; si++) {
        final s = sessions[si];
        final w = unit * s.columns.length;
        top.add(pw.Container(
          width: w,
          height: 30,
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(s.title, style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white)),
              pw.Text(
                '${SupervisorTableData.fmt(s.start)} - ${SupervisorTableData.fmt(s.end)}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.indigo100),
              ),
            ],
          ),
        ));
        for (final c in s.columns) {
          bottom.add(pw.Container(
            width: unit,
            height: 20,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo100,
              border: pw.Border(right: pw.BorderSide(color: PdfColors.white, width: 1)),
            ),
            child: pw.Text(
              '${SupervisorTableData.fmt(c.start)} - ${SupervisorTableData.fmt(c.end)}',
              style: pw.TextStyle(font: bold, fontSize: 8.5, color: PdfColors.indigo900),
            ),
          ));
        }
        if (si < sessions.length - 1) {
          top.add(pw.Container(width: _gapW, height: 30, color: PdfColors.amber50));
          bottom.add(pw.Container(width: _gapW, height: 20, color: PdfColors.amber50));
        }
      }
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: _roomW,
            height: 50,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: const pw.BorderRadius.only(topLeft: pw.Radius.circular(7)),
            ),
            child: pw.Text('SALON', style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white)),
          ),
          pw.Column(children: [pw.Row(children: top), pw.Row(children: bottom)]),
        ],
      );
    }

    pw.Widget roomRow(ExamRoom room, int idx) {
      final List<pw.Widget> cells = [];
      for (int si = 0; si < sessions.length; si++) {
        final s = sessions[si];
        for (final cell in data.cellsFor(room, s)) {
          final bool has = cell.name.isNotEmpty;
          final PdfColor bg = has
              ? (cell.custom ? PdfColors.purple50 : PdfColors.indigo50)
              : PdfColors.red50;
          final PdfColor border = has
              ? (cell.custom ? PdfColors.purple200 : PdfColors.indigo200)
              : PdfColors.red200;
          cells.add(pw.Container(
            width: unit * data.spanOf(s, cell.seg),
            height: rowH,
            padding: const pw.EdgeInsets.all(1.5),
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              decoration: pw.BoxDecoration(
                color: bg,
                borderRadius: pw.BorderRadius.circular(5),
                border: pw.Border.all(color: border, width: 0.7),
              ),
              child: pw.Text(
                has ? cell.name : '—',
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: pw.TextStyle(
                  font: has ? bold : font,
                  fontSize: nameFont,
                  color: has ? PdfColors.grey900 : PdfColors.red600,
                ),
              ),
            ),
          ));
        }
        if (si < sessions.length - 1) {
          cells.add(pw.Container(width: _gapW, height: rowH, color: PdfColors.amber50));
        }
      }
      final bool last = idx == rooms.length - 1;
      return pw.Row(
        children: [
          pw.Container(
            width: _roomW,
            height: rowH,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: idx.isEven ? PdfColors.grey200 : PdfColors.grey300,
              border: const pw.Border(bottom: pw.BorderSide(color: PdfColors.white, width: 1)),
              borderRadius: last ? const pw.BorderRadius.only(bottomLeft: pw.Radius.circular(7)) : null,
            ),
            child: pw.Text(
              room.classroomName,
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              style: pw.TextStyle(font: bold, fontSize: roomy ? 11 : 9.5, color: PdfColors.blueGrey900),
            ),
          ),
          ...cells,
        ],
      );
    }

    pw.Widget footer(int page, int total) {
      return pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [
              _legend(PdfColors.indigo50, PdfColors.indigo200, 'Atanmış gözetmen', font),
              pw.SizedBox(width: 14),
              _legend(PdfColors.purple50, PdfColors.purple200, 'Salona özel bölünmüş devre', font),
              pw.SizedBox(width: 14),
              _legend(PdfColors.red50, PdfColors.red200, 'Gözetmen atanmamış', font),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'eduKN • Gözetmen Çizelgesi • ${data.assignedCells}/${data.totalCells} görev atanmış',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                ),
                pw.Text(
                  'Sayfa $page / $total  •  $printedAt',
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
        ],
      );
    }

    int globalIdx = 0;
    for (int p = 0; p < chunks.length; p++) {
      final chunk = chunks[p];
      final startIdx = globalIdx;
      globalIdx += chunk.length;
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(_margin),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (p == 0) ...[banner(), pw.SizedBox(height: 10)],
              headerRows(),
              for (int r = 0; r < chunk.length; r++) roomRow(chunk[r], startIdx + r),
              pw.Spacer(),
              footer(p + 1, chunks.length),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _infoItem(String label, String value, pw.Font font, pw.Font bold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 1.5),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.indigo900)),
      ],
    );
  }

  static pw.Widget _legend(PdfColor bg, PdfColor border, String text, pw.Font font) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(3),
            border: pw.Border.all(color: border, width: 0.7),
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
      ],
    );
  }
}

