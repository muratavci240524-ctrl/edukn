import 'dart:typed_data';
import 'package:printing/printing.dart';

/// Web dışı platformlarda kullanılmaz (false döner).
Future<bool> shareFileWeb({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? title,
  String? text,
}) async =>
    false;

/// Web dışı platformlarda (Android, iOS vb.) Printing.sharePdf ile dosya kaydeder / paylaşır.
Future<void> downloadFileUniversal({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/pdf',
}) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

/// Web dışı platformlarda Printing.layoutPdf ile yazdırma penceresini açar.
Future<void> printFileUniversal({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/pdf',
}) async {
  await Printing.layoutPdf(onLayout: (_) => bytes, name: fileName);
}
