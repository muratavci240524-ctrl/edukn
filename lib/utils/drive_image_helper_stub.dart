import 'package:flutter/material.dart';

/// Native (non-web) platforms: size is resolved from downloaded bytes instead.
Future<Size?> nativeWebImageSize(List<String> candidateUrls) async => null;

Widget buildNativeWebDriveImage({
  required List<String> candidateUrls,
  BoxFit fit = BoxFit.contain,
}) {
  if (candidateUrls.isEmpty) {
    return const Center(
      child: Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
  return Image.network(
    candidateUrls.first,
    fit: fit,
    errorBuilder: (ctx, err, st) {
      if (candidateUrls.length > 1) {
        return Image.network(
          candidateUrls[1],
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

