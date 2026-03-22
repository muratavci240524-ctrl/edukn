import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EduKnDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final IconData? prefixIcon;
  final bool isExpanded;
  final Color? fillColor;

  const EduKnDropdown({
    Key? key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.validator,
    this.prefixIcon,
    this.isExpanded = true,
    this.fillColor = const Color(0xFFF8FAFC),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: isExpanded,
      borderRadius: BorderRadius.circular(16),
      menuMaxHeight: 300,
      dropdownColor: Colors.white,
      elevation: 16,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.indigo),
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1E293B),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: Colors.indigo) : null,
        filled: true,
        fillColor: fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}
