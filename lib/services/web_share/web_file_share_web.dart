// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:convert';
import 'package:printing/printing.dart';
import 'sanitize_file_name.dart';

/// Tarayıcının Web Share API'si ile DOSYAYI EKLİ olarak paylaşır
Future<bool> shareFileWeb({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? title,
  String? text,
}) async {
  try {
    final nav = js.context['navigator'];
    if (nav is! js.JsObject) return false;
    if (nav['share'] == null || nav['canShare'] == null) return false;

    final safeFileName = sanitizeFileName(fileName);
    final uint8Array = js.JsObject(js.context['Uint8Array'], [bytes]);
    final file = js.JsObject(js.context['File'], [
      js.JsObject.jsify([uint8Array]),
      safeFileName,
      js.JsObject.jsify({'type': mimeType}),
    ]);
    final data = js.JsObject.jsify({
      'files': [file],
      if (title != null) 'title': title,
      if (text != null) 'text': text,
    });
    final can = nav.callMethod('canShare', [data]);
    if (can != true) return false;

    final done = Completer<bool>();
    final promise = nav.callMethod('share', [data]);
    if (promise is! js.JsObject) return false;
    promise.callMethod('then', [
      (dynamic _) {
        if (!done.isCompleted) done.complete(true);
      },
      (dynamic e) {
        if (!done.isCompleted) done.complete(e.toString().contains('AbortError'));
      },
    ]);
    return await done.future;
  } catch (_) {
    return false;
  }
}

/// Tarayıcıda (Web) PDF ve belgeleri doğrudan ve eksiksiz indirir.
/// Chrome'un 0 KB / bozuk dosya hatasını engellemek için:
/// Blob URL oluşturulur, gizli bağlantı tıklanır ve URL HEMEN REVOKE EDİLMEZ (5 dakika tutulur).
Future<void> downloadFileUniversal({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/pdf',
}) async {
  if (bytes.isEmpty) {
    print('❌ downloadFileUniversal: bytes BOŞ (0 bayt)! İndirme durduruldu.');
    throw Exception('İndirilecek PDF içeriği boş (0 bayt).');
  }

  final safeFileName = sanitizeFileName(fileName);
  print('💾 downloadFileUniversal: $safeFileName başlatılıyor (${bytes.length} bayt)');

  // 1. Ana Yöntem: dart:html Blob + Gecikmeli Revoke (Chrome için en güvenilir native yol)
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', safeFileName)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();

    // Chrome indirmeyi tamamlayabilsin diye URL'yi 5 dakika bellekte tut
    Future.delayed(const Duration(minutes: 5), () {
      try {
        anchor.remove();
        html.Url.revokeObjectUrl(url);
      } catch (_) {}
    });
    print('✅ downloadFileUniversal: Blob indirme tetiklendi ($safeFileName)');
    return;
  } catch (e) {
    print('⚠️ Blob indirme hatası: $e, alternatiflere geçiliyor...');
  }

  // 2. Alternatif: index.html içerisindeki akıllı JS fonksiyonu
  try {
    final base64String = base64Encode(bytes);
    if (js.context.hasProperty('__eduKnDownloadPdf')) {
      final res = js.context.callMethod('__eduKnDownloadPdf', [base64String, safeFileName]);
      if (res == true) {
        print('✅ downloadFileUniversal: __eduKnDownloadPdf ile başarıyla indirildi.');
        return;
      }
    }
  } catch (_) {}

  // 3. Alternatif: Base64 Data URI
  try {
    final base64String = base64Encode(bytes);
    final dataUri = 'data:$mimeType;base64,$base64String';
    final anchor = html.AnchorElement(href: dataUri)
      ..target = '_blank'
      ..download = safeFileName;
    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    print('✅ downloadFileUniversal: Data URI ile indirme tetiklendi.');
    return;
  } catch (_) {}

  // 4. Son Fallback: Printing.sharePdf
  try {
    await Printing.sharePdf(bytes: bytes, filename: safeFileName);
  } catch (_) {}
}

/// Tarayıcıda PDF belgesini doğrudan yazdırır.
/// PDF Blob'unu doğrudan yeni sekmede açar veya Printing.layoutPdf çalıştırır.
Future<void> printFileUniversal({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/pdf',
}) async {
  if (bytes.isEmpty) {
    print('❌ printFileUniversal: bytes BOŞ (0 bayt)! Yazdırma durduruldu.');
    throw Exception('Yazdırılacak PDF içeriği boş (0 bayt).');
  }

  final safeFileName = sanitizeFileName(fileName);
  print('🖨️ printFileUniversal: $safeFileName başlatılıyor (${bytes.length} bayt)');

  // 1. Ana Yöntem: Blob URL ile yeni pencerede açarak yerel Chrome PDF görüntüleyicisini ve yazdırma menüsünü getir
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    Future.delayed(const Duration(minutes: 10), () {
      try {
        html.Url.revokeObjectUrl(url);
      } catch (_) {}
    });
    print('✅ printFileUniversal: Blob yeni sekmede açıldı ($safeFileName)');
    return;
  } catch (e) {
    print('⚠️ Blob sekme açma hatası: $e, Printing.layoutPdf deneniyor...');
  }

  // 2. Alternatif: index.html JS fonksiyonu
  try {
    if (js.context.hasProperty('__eduKnPrintPdf')) {
      final base64String = base64Encode(bytes);
      final res = js.context.callMethod('__eduKnPrintPdf', [base64String, safeFileName]);
      if (res == true) return;
    }
  } catch (_) {}

  // 3. Fallback: Printing.layoutPdf
  try {
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: safeFileName,
    );
  } catch (_) {}
}
