import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Üst alan etiketi (kesik çizgili eski floating label yerine modern SaaS üst başlık)
class AcademicFieldLabel extends StatelessWidget {
  final String label;
  final String? trailingText;

  const AcademicFieldLabel(this.label, {super.key, this.trailingText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (trailingText != null && trailingText!.isNotEmpty)
            Text(
              trailingText!,
              style: GoogleFonts.inter(
                fontSize: 11.2,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration buildAcademicInputDecoration({
  String? hint,
  IconData? icon,
  Color accentColor = const Color(0xFF4F46E5),
  Widget? suffix,
  bool isMultiline = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(
      fontSize: 13.2,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF94A3B8),
    ),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    hoverColor: const Color(0xFFF1F5F9),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: isMultiline ? 13 : 12.5,
    ),
    prefixIcon: icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: accentColor),
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 34),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: accentColor, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
    ),
  );
}

/// Taşma yapmayan (`isExpanded: true`) premium açılır seçim alanı
class AcademicDropdownField<T> extends StatelessWidget {
  final String? label;
  final String? trailingText;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final String? hint;
  final Color accentColor;

  const AcademicDropdownField({
    super.key,
    this.label,
    this.trailingText,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.hint,
    this.accentColor = const Color(0xFF4F46E5),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null && label!.isNotEmpty)
          AcademicFieldLabel(label!, trailingText: trailingText),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF64748B),
            size: 20,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: buildAcademicInputDecoration(
            hint: hint,
            icon: icon,
            accentColor: accentColor,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Premium metin giriş alanı
class AcademicTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? trailingText;
  final String? hint;
  final IconData? icon;
  final Color accentColor;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final TextAlign textAlign;

  const AcademicTextField({
    super.key,
    this.controller,
    this.label,
    this.trailingText,
    this.hint,
    this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null && label!.isNotEmpty)
          AcademicFieldLabel(label!, trailingText: trailingText),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          textAlign: textAlign,
          style: GoogleFonts.inter(
            fontSize: 13.6,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: buildAcademicInputDecoration(
            hint: hint,
            icon: icon,
            accentColor: accentColor,
            isMultiline: maxLines > 1,
          ),
        ),
      ],
    );
  }
}

/// Premium arama çubuğu (temizle butonlu ve ikon rozetli)
class AcademicSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final Color accentColor;
  final String? label;

  const AcademicSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.accentColor = const Color(0xFF4F46E5),
    this.label,
  });

  @override
  State<AcademicSearchField> createState() => _AcademicSearchFieldState();
}

class _AcademicSearchFieldState extends State<AcademicSearchField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null && widget.label!.isNotEmpty)
          AcademicFieldLabel(widget.label!),
        TextField(
          controller: _ctrl,
          onChanged: (v) {
            setState(() {});
            widget.onChanged(v);
          },
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: buildAcademicInputDecoration(
            hint: widget.hint,
            icon: Icons.search_rounded,
            accentColor: widget.accentColor,
            suffix: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: Color(0xFF64748B),
                    ),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {});
                      widget.onChanged('');
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// Eski tip ChoiceChip / FilterChip yerine modern seçilebilir hap buton
class AcademicChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color accentColor;
  final bool compact;

  const AcademicChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 14,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      accentColor,
                      Color.lerp(accentColor, const Color(0xFF0F172A), 0.18)!,
                    ],
                  )
                : null,
            color: selected ? null : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accentColor : const Color(0xFFD5DFEC),
              width: 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 64,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : accentColor,
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 12.2 : 12.8,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
