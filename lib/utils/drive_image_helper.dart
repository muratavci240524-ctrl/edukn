import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'drive_image_helper_stub.dart'
    if (dart.library.html) 'drive_image_helper_web.dart';

class DriveImageHelper {
  /// Extracts a Google Drive File ID from any common Drive link format:
  /// - `https://drive.google.com/uc?export=view&id=FILE_ID`
  /// - `https://drive.google.com/file/d/FILE_ID/view?usp=sharing`
  /// - `https://drive.google.com/open?id=FILE_ID`
  /// - `https://drive.google.com/thumbnail?id=FILE_ID&sz=w1000`
  /// - `https://lh3.googleusercontent.com/d/FILE_ID=w1000`
  static String? extractDriveFileId(String? rawUrl) {
    if (rawUrl == null) return null;
    final url = rawUrl.trim();
    if (url.isEmpty) return null;

    // 1. Query param ?id=... or &id=...
    final idParam = RegExp(r'[?&]id=([a-zA-Z0-9_-]{15,})').firstMatch(url);
    if (idParam != null) return idParam.group(1);

    // 2. /file/d/FILE_ID or /d/FILE_ID
    final dPath = RegExp(r'/d/([a-zA-Z0-9_-]{15,})').firstMatch(url);
    if (dPath != null) return dPath.group(1);

    // 3. Raw file ID passed directly
    if (!url.contains('/') &&
        !url.contains(':') &&
        RegExp(r'^[a-zA-Z0-9_-]{20,50}$').hasMatch(url)) {
      return url;
    }

    return null;
  }

  /// Normalizes a Google Drive link into a high-res thumbnail URL suitable for display.
  static String normalizeDriveImageUrl(String? rawUrl, {String? driveFileId}) {
    final fileId = (driveFileId != null && driveFileId.trim().isNotEmpty)
        ? driveFileId.trim()
        : extractDriveFileId(rawUrl);
    if (fileId != null && fileId.isNotEmpty) {
      return 'https://drive.google.com/thumbnail?id=$fileId&sz=w1200';
    }
    return (rawUrl ?? '').trim();
  }

  /// Tablodaki görseller sabit ölçekte üretiliyor: tek sütun soru ≈ 600–630 px,
  /// çift sütun (geniş) soru ≈ 1100+ px genişliğinde. Bu yüzden karar en/boy oranına
  /// değil, gerçek piksel GENİŞLİĞİNE göre verilir.
  static const double kWidePixelThreshold = 900;

  /// Otomatik sütun algoritmasının sürümü (eski hatalı oran tabanlı kararları yeniden hesaplatmak için).
  static const int kAutoWideVersion = 2;

  static bool shouldBeWide(Size size) {
    if (size.width <= 0 || size.height <= 0) return false;
    return size.width >= kWidePixelThreshold;
  }

  /// Sorunun görsel boyutunu (piksel) bulur: base64 → bytes decode,
  /// Web'de Drive/URL → `<img>` naturalWidth/naturalHeight, Native'de → bytes indirip decode.
  static Future<Size?> getImageSize({
    String? base64Image,
    String? imageUrl,
    String? driveFileId,
  }) async {
    Future<Size?> decodeSize(Uint8List bytes) async {
      try {
        final img = await decodeImageFromList(bytes);
        final s = Size(img.width.toDouble(), img.height.toDouble());
        img.dispose();
        return s;
      } catch (_) {
        return null;
      }
    }

    if (base64Image != null && base64Image.trim().isNotEmpty) {
      try {
        String clean = base64Image.trim();
        if (clean.contains(',')) clean = clean.substring(clean.indexOf(',') + 1);
        final s = await decodeSize(base64Decode(clean.replaceAll(RegExp(r'\s+'), '')));
        if (s != null) return s;
      } catch (_) {}
    }

    final candidates = candidateUrlsForDisplay(imageUrl, driveFileId: driveFileId);
    if (candidates.isEmpty) return null;

    if (kIsWeb) {
      final s = await nativeWebImageSize(candidates);
      if (s != null) return s;
    }

    final bytes = await fetchImageBytes(imageUrl, driveFileId: driveFileId);
    if (bytes != null) return decodeSize(bytes);
    return null;
  }

  /// Ordered candidate URLs for browser `<img>` / `Image.network` display.
  static List<String> candidateUrlsForDisplay(
    String? rawUrl, {
    String? driveFileId,
  }) {
    final fileId = (driveFileId != null && driveFileId.trim().isNotEmpty)
        ? driveFileId.trim()
        : extractDriveFileId(rawUrl);
    if (fileId != null && fileId.isNotEmpty) {
      final lh3Url = 'https://lh3.googleusercontent.com/d/$fileId=w1200';
      final thumbUrl = 'https://drive.google.com/thumbnail?id=$fileId&sz=w1200';
      final directDl =
          'https://drive.usercontent.google.com/download?id=$fileId&export=download';
      final wsrvThumb =
          'https://wsrv.nl/?url=${Uri.encodeComponent(thumbUrl)}&output=png';
      final wsrvDirect =
          'https://wsrv.nl/?url=${Uri.encodeComponent(directDl)}&output=png';
      final ucViewUrl = 'https://drive.google.com/uc?export=view&id=$fileId';
      return [lh3Url, thumbUrl, wsrvThumb, wsrvDirect, ucViewUrl];
    }
    final clean = (rawUrl ?? '').trim();
    return clean.isEmpty ? const [] : [clean];
  }

  /// Ordered candidate URLs for downloading raw image bytes (`http.get`) in Web & Native.
  static List<String> candidateUrlsForByteFetch(
    String? rawUrl, {
    String? driveFileId,
  }) {
    final fileId = (driveFileId != null && driveFileId.trim().isNotEmpty)
        ? driveFileId.trim()
        : extractDriveFileId(rawUrl);
    if (fileId != null && fileId.isNotEmpty) {
      final thumbUrl = 'https://drive.google.com/thumbnail?id=$fileId&sz=w1200';
      final directDl =
          'https://drive.usercontent.google.com/download?id=$fileId&export=download';
      final lh3Url = 'https://lh3.googleusercontent.com/d/$fileId=w1200';
      return [
        'https://wsrv.nl/?url=${Uri.encodeComponent(thumbUrl)}&output=png',
        'https://wsrv.nl/?url=${Uri.encodeComponent(directDl)}&output=png',
        'https://corsproxy.io/?${Uri.encodeComponent(thumbUrl)}',
        lh3Url,
        thumbUrl,
      ];
    }
    final clean = (rawUrl ?? '').trim();
    if (clean.isEmpty) return const [];
    return [
      clean,
      'https://wsrv.nl/?url=${Uri.encodeComponent(clean)}&output=png',
    ];
  }

  /// Verifies that bytes start with a valid PNG, JPEG, GIF, or WebP magic header
  /// so an HTML error/login response is never treated as image bytes.
  static bool isValidImageBytes(Uint8List bytes) {
    if (bytes.length < 16) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    // GIF: 47 49 46 38 ("GIF8")
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    // WebP: "RIFF"...."WEBP"
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  /// Downloads raw image bytes from either a standard URL or a Google Drive URL/fileId.
  static Future<Uint8List?> fetchImageBytes(
    String? rawUrl, {
    String? driveFileId,
    Duration perTryTimeout = const Duration(seconds: 5),
  }) async {
    final cleanUrl = (rawUrl ?? '').trim();
    if (cleanUrl.startsWith('data:')) {
      final comma = cleanUrl.indexOf(',');
      if (comma != -1) {
        try {
          final decoded = base64Decode(cleanUrl.substring(comma + 1).trim());
          if (isValidImageBytes(decoded)) return decoded;
        } catch (_) {}
      }
    }

    final candidates = candidateUrlsForByteFetch(
      cleanUrl,
      driveFileId: driveFileId,
    );
    for (final url in candidates) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(perTryTimeout);
        if (res.statusCode == 200 && isValidImageBytes(res.bodyBytes)) {
          return res.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Renders a question image from `base64Image`, `imageUrl`, or `driveFileId`.
  /// On Flutter Web, Google Drive images without `base64Image` use a native HTML `<img>`
  /// element with automatic multi-endpoint fallback so browser CORS never blocks them.
  static Widget buildPoolQuestionImage({
    String? base64Image,
    String? imageUrl,
    String? driveFileId,
    BoxFit fit = BoxFit.contain,
  }) {
    if (base64Image != null && base64Image.trim().isNotEmpty) {
      try {
        String clean = base64Image.trim();
        if (clean.contains(',')) {
          clean = clean.substring(clean.indexOf(',') + 1);
        }
        clean = clean.replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(clean);
        if (bytes.isNotEmpty) {
          return Image.memory(bytes, fit: fit);
        }
      } catch (_) {}
    }

    final fileId = (driveFileId != null && driveFileId.trim().isNotEmpty)
        ? driveFileId.trim()
        : extractDriveFileId(imageUrl);
    final candidates = candidateUrlsForDisplay(
      imageUrl,
      driveFileId: fileId,
    );

    if (candidates.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    if (kIsWeb && fileId != null && fileId.isNotEmpty) {
      return buildNativeWebDriveImage(
        candidateUrls: candidates,
        fit: fit,
      );
    }

    return Image.network(
      candidates.first,
      fit: fit,
      errorBuilder: (ctx, err, st) {
        if (candidates.length > 1) {
          return Image.network(
            candidates[1],
            fit: fit,
            errorBuilder: (_, __, ___) {
              if (candidates.length > 2) {
                return Image.network(
                  candidates[2],
                  fit: fit,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                );
              }
              return const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
              );
            },
          );
        }
        return const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.grey),
        );
      },
    );
  }
}

