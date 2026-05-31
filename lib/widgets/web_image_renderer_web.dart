// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredViews = {};

Widget buildWebImage(
  String assetPath, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) {
  // Use a unique viewId based on the asset path
  final viewId = 'web-image-${assetPath.replaceAll('/', '-').replaceAll('.', '-')}-${width ?? 0}-${height ?? 0}';
  
  if (!_registeredViews.contains(viewId)) {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      // In Flutter Web, assets are served at "assets/assets/..." or "assets/..."
      // The native ImageElement src should point to "assets/$assetPath" to load correctly.
      final img = html.ImageElement()
        ..src = 'assets/$assetPath'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..style.userSelect = 'none'
        ..style.display = 'block';
        
      switch (fit) {
        case BoxFit.contain:
          img.style.objectFit = 'contain';
          break;
        case BoxFit.cover:
          img.style.objectFit = 'cover';
          break;
        case BoxFit.fill:
          img.style.objectFit = 'fill';
          break;
        default:
          img.style.objectFit = 'contain';
      }
      return img;
    });
    _registeredViews.add(viewId);
  }

  return SizedBox(
    width: width,
    height: height,
    child: HtmlElementView(
      viewType: viewId,
    ),
  );
}
