import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Tahtaya eklenecek resmi dosyadan seçtirir.
Future<Uint8List?> wbPickImageBytes() async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    withData: true,
  );
  return result?.files.single.bytes;
}

class WbPickedFile {
  WbPickedFile(this.name, this.ext, this.bytes);
  final String name;
  final String ext;
  final Uint8List bytes;
}

/// Ders notu olarak eklenecek PDF / PNG / JPEG dosyalarını (birden fazla) seçtirir.
Future<List<WbPickedFile>> wbPickNoteFiles() async {
  final r = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    allowMultiple: true,
    withData: true,
  );
  if (r == null) return [];
  return [
    for (final f in r.files)
      if (f.bytes != null)
        WbPickedFile(f.name, (f.extension ?? '').toLowerCase(), f.bytes!),
  ];
}

class WbRasterPage {
  WbRasterPage(this.png, this.width, this.height);
  final Uint8List png;
  final int width;
  final int height;
}

/// PDF'in her sayfasını kendi boyutunda PNG'ye çevirir (en fazla [maxPages] sayfa).
Future<List<WbRasterPage>> wbRasterPdf(
  Uint8List pdfBytes, {
  double dpi = 110,
  int maxPages = 60,
}) async {
  final out = <WbRasterPage>[];
  await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
    out.add(WbRasterPage(await page.toPng(), page.width, page.height));
    if (out.length >= maxPages) break;
  }
  return out;
}

/// Tek sayfayı PNG olarak kaydeder / indirir.
Future<void> wbSavePng(String name, Uint8List bytes) async {
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: 'png',
    mimeType: MimeType.png,
  );
}

class WbPdfPage {
  WbPdfPage(this.png, this.width, this.height);
  final Uint8List png;
  final double width;
  final double height;
}

/// Her sayfa KENDİ boyutunda olacak şekilde PDF üretir.
Future<Uint8List> wbBuildPdf(List<WbPdfPage> pages) async {
  final doc = pw.Document();
  for (final p in pages) {
    final img = pw.MemoryImage(p.png);
    // piksel -> pt (yaklaşık 150 dpi görüntü => 0.48)
    final w = p.width * 0.48;
    final h = p.height * 0.48;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w, h, marginAll: 0),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(img, fit: pw.BoxFit.fill),
        ),
      ),
    );
  }
  return Uint8List.fromList(await doc.save());
}

/// Tüm sayfaları tek bir PDF dosyasına çevirip kaydeder.
Future<void> wbSavePdf(String name, List<WbPdfPage> pages) async {
  final bytes = await wbBuildPdf(pages);
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: 'pdf',
    mimeType: MimeType.pdf,
  );
}
