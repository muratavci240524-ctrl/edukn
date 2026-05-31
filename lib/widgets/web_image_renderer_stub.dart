import 'package:flutter/material.dart';

Widget buildWebImage(
  String assetPath, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) {
  return Image.asset(
    assetPath,
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.high,
  );
}
