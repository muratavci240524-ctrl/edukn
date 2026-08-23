import 'package:flutter/material.dart';

/// Standart eduKN AppBar Geri Butonu
/// Okul Türü detay sayfasındaki geri butonuyla birebir aynı tasarıma (Icons.arrow_back_ios_new_rounded, 20px, Colors.indigo) sahiptir.
class EduknBackButton extends StatelessWidget {
  final Color? color;
  final double size;
  final VoidCallback? onPressed;
  final String? tooltip;

  const EduknBackButton({
    Key? key,
    this.color,
    this.size = 20,
    this.onPressed,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color effectiveColor = color ?? IconTheme.of(context).color ?? Colors.indigo;

    if (color == null) {
      final iconColor = IconTheme.of(context).color;
      if (iconColor != null && iconColor != Colors.black && iconColor != Colors.black87) {
        effectiveColor = iconColor;
      } else {
        final appBarTheme = AppBarTheme.of(context);
        final bg = appBarTheme.backgroundColor;
        if (bg != null) {
          final isDark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
          effectiveColor = isDark ? Colors.white : Colors.indigo;
        }
      }
    }

    return IconButton(
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        size: size,
        color: effectiveColor,
      ),
      tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.maybePop(context);
        }
      },
    );
  }
}
