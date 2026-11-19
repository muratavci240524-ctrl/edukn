// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredDriveImgViews = {};

/// Reads the natural pixel size of an image via a browser `<img>` element.
/// Works for cross-origin Drive images without CORS (only dimensions are read).
Future<Size?> nativeWebImageSize(List<String> candidateUrls) async {
  for (final url in candidateUrls) {
    final img = html.ImageElement()..referrerPolicy = 'no-referrer';
    final completer = Completer<Size?>();
    img.onLoad.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete(
          Size(img.naturalWidth.toDouble(), img.naturalHeight.toDouble()),
        );
      }
    });
    img.onError.first.then((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    img.src = url;
    final result = await completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (result != null && result.width > 1 && result.height > 1) {
      return result;
    }
  }
  return null;
}

Widget buildNativeWebDriveImage({
  required List<String> candidateUrls,
  BoxFit fit = BoxFit.contain,
}) {
  if (candidateUrls.isEmpty) {
    return const Center(
      child: Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }

  final String primaryKey =
      candidateUrls.first.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final String fitKey = fit.name;
  final String viewId = 'edukn-drive-img-v3-$primaryKey-$fitKey';

  if (!_registeredDriveImgViews.contains(viewId)) {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      final container = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'flex'
        ..style.alignItems = 'center'
        ..style.justifyContent = 'center'
        ..style.pointerEvents = 'none'
        ..style.overflow = 'hidden';

      final img = html.ImageElement()
        ..referrerPolicy = 'no-referrer'
        ..src = candidateUrls.first
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.userSelect = 'none'
        ..style.pointerEvents = 'none'
        ..style.display = 'block';

      switch (fit) {
        case BoxFit.cover:
          img.style.objectFit = 'cover';
          break;
        case BoxFit.fill:
          img.style.objectFit = 'fill';
          break;
        default:
          img.style.objectFit = 'contain';
      }

      int currentIndex = 0;
      img.onError.listen((_) {
        currentIndex++;
        if (currentIndex < candidateUrls.length) {
          img.src = candidateUrls[currentIndex];
        } else {
          img.style.display = 'none';
          final fallback = html.DivElement()
            ..style.padding = '8px'
            ..style.textAlign = 'center'
            ..style.color = '#64748B'
            ..style.fontSize = '11px'
            ..style.fontFamily = 'Inter, sans-serif'
            ..style.lineHeight = '1.35'
            ..innerText =
                '🔒 Drive Görseli Kısıtlı\nGoogle Drive klasörünü "Bağlantıya sahip olan herkes" yapın';
          container.append(fallback);
        }
      });

      container.append(img);
      return container;
    });
    _registeredDriveImgViews.add(viewId);
  }

  return SizedBox.expand(
    child: IgnorePointer(
      child: HtmlElementView(viewType: viewId),
    ),
  );
}
