import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Rol anahtarlarını kullanıcı dostu Türkçe etiketlere dönüştürür.
class InventoryRoleHelper {
  static String prettyRole(String rawRole) {
    final key = rawRole.trim().toLowerCase();
    switch (key) {
      case 'admin':
      case 'kurucu':
        return 'Kurum Yöneticisi';
      case 'genel_mudur':
        return 'Genel Müdür';
      case 'mudur':
        return 'Müdür';
      case 'mudur_yardimcisi':
        return 'Müdür Yrd.';
      case 'depo':
      case 'depo_sorumlusu':
        return 'Depo Sorumlusu';
      case 'satin_alma':
      case 'satinalma':
        return 'Satın Alma';
      case 'muhasebe':
      case 'mali_isler':
        return 'Mali İşler';
      case 'insan_kaynaklari':
      case 'hr':
        return 'İnsan Kaynakları';
      case 'ogretmen':
        return 'Öğretmen';
      case 'rehber_ogretmen':
      case 'psikolojik_danisman':
        return 'Rehber Öğretmen';
      case 'guvenlik':
        return 'Güvenlik';
      case 'saglik_personeli':
        return 'Sağlık Birimi';
      case 'destek_hizmetleri':
        return 'Destek Birimi';
      case 'personel':
        return 'Personel';
      default:
        if (key.isEmpty) return 'Personel';
        return rawRole
            .replaceAll('_', ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ');
    }
  }

  static String initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Tüm Depo & Satın Alma alt pencerelerini ekranın TAM ALTINA sıfır oturacak şekilde açar.
Future<T?> showInventoryBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext sheetContext) builder,
  double maxWidth = 720,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.50),
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: builder(ctx),
      ),
    ),
  );
}

/// Alt pencere (Bottom Sheet) için tam alttan sıfır oturan, modern başlık ve sabit alt buton destekli çerçeve.
class InventoryBottomSheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Color? iconBgColor;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onClose;
  final double maxHeightFactor;

  const InventoryBottomSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    this.iconBgColor,
    required this.child,
    this.footer,
    this.onClose,
    this.maxHeightFactor = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final bottomSafe = mq.padding.bottom;
    final maxSheetHeight = mq.size.height * maxHeightFactor;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.zero,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x290F172A),
                blurRadius: 36,
                offset: Offset(0, -10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Üst Sürükleme Çubuğu + Modern Başlık Alanı
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 10, 14, 16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 4.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: iconBgColor ??
                                  accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Icon(icon, color: accentColor, size: 22),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle!,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed:
                                onClose ?? () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFF8FAFC),
                              foregroundColor: const Color(0xFF475569),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Kaydırılabilir Gövde
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      22,
                      18,
                      22,
                      footer == null
                          ? (keyboardInset > 0 ? 20 : 22 + bottomSafe)
                          : 18,
                    ),
                    child: child,
                  ),
                ),

                // Sabit Alt Eylem Çubuğu (Footer)
                if (footer != null)
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      22,
                      14,
                      22,
                      keyboardInset > 0 ? 14 : 16 + bottomSafe,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(
                        top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      ),
                    ),
                    child: footer!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Form alanı üst başlığı
class InventoryFieldLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  final String? trailingText;

  const InventoryFieldLabel(
    this.label, {
    super.key,
    this.isRequired = false,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7, left: 2),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                text: label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                  letterSpacing: 0.1,
                ),
                children: isRequired
                    ? const [
                        TextSpan(
                          text: ' *',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ]
                    : const [],
              ),
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText!,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }
}

/// Premium SaaS tarzı metin giriş alanı (eski tip gri/kesik çerçevelerin yerine).
class InventoryTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final bool isRequired;
  final String? trailingText;
  final String? hint;
  final IconData? icon;
  final Color accentColor;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? minLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final TextAlign textAlign;
  final bool readOnly;
  final VoidCallback? onTap;

  const InventoryTextField({
    super.key,
    required this.controller,
    this.label,
    this.isRequired = false,
    this.trailingText,
    this.hint,
    this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.validator,
    this.onChanged,
    this.suffix,
    this.textAlign = TextAlign.start,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null && label!.isNotEmpty)
          InventoryFieldLabel(
            label!,
            isRequired: isRequired,
            trailingText: trailingText,
          ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          minLines: minLines,
          validator: validator,
          onChanged: onChanged,
          textAlign: textAlign,
          readOnly: readOnly,
          onTap: onTap,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: buildInventoryInputDecoration(
            hint: hint,
            icon: icon,
            accentColor: accentColor,
            suffix: suffix,
            isMultiline: maxLines > 1,
          ),
        ),
      ],
    );
  }
}

/// Premium SaaS tarzı açılır seçim kutusu (Dropdown)
class InventoryDropdownField<T> extends StatelessWidget {
  final String? label;
  final bool isRequired;
  final String? trailingText;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final String? hint;
  final Color accentColor;

  const InventoryDropdownField({
    super.key,
    this.label,
    this.isRequired = false,
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
          InventoryFieldLabel(
            label!,
            isRequired: isRequired,
            trailingText: trailingText,
          ),
        DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF64748B),
            size: 20,
          ),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: const TextStyle(
            fontSize: 13.8,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: buildInventoryInputDecoration(
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

InputDecoration buildInventoryInputDecoration({
  String? hint,
  IconData? icon,
  Color accentColor = const Color(0xFF4F46E5),
  Widget? suffix,
  bool isMultiline = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
    ),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    hoverColor: const Color(0xFFF1F5F9),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: isMultiline ? 14 : 13.5,
    ),
    prefixIcon: icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: accentColor),
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 36),
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
      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.3),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
    ),
  );
}

/// Modern arama kutusu
class InventorySearchField extends StatelessWidget {
  final TextEditingController controller;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const InventorySearchField({
    super.key,
    required this.controller,
    required this.value,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: 13.8,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 13.2,
            fontWeight: FontWeight.w400,
            color: Color(0xFF94A3B8),
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 17,
                color: Color(0xFF4F46E5),
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 34,
          ),
          suffixIcon: value.isNotEmpty
              ? IconButton(
                  tooltip: 'Temizle',
                  onPressed: onClear,
                  icon: const Icon(
                    Icons.cancel_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                )
              : null,
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
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
          ),
        ),
      ),
    );
  }
}

/// Onay yetkilisi veya depocu seçimi için avatar + okunaklı rol rozetli şık seçim kartları
class InventoryStaffMultiSelector extends StatelessWidget {
  final List<({String uid, String name, String role})> staffList;
  final Set<String> selectedUids;
  final ValueChanged<String> onToggle;
  final String emptyText;

  const InventoryStaffMultiSelector({
    super.key,
    required this.staffList,
    required this.selectedUids,
    required this.onToggle,
    this.emptyText = 'Uygun yetkili personel kaydı bulunamadı.',
  });

  @override
  Widget build(BuildContext context) {
    if (staffList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: staffList.map((s) {
        final selected = selectedUids.contains(s.uid);
        final roleLabel = InventoryRoleHelper.prettyRole(s.role);
        return InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => onToggle(s.uid),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEEF2FF) : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? const Color(0xFF4F46E5)
                    : const Color(0xFFD5DFEC),
                width: selected ? 1.6 : 1.1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : Text(
                          InventoryRoleHelper.initials(s.name),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF475569),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF1E1B4B)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      roleLabel,
                      style: TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? const Color(0xFF4F46E5)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Şık Switch/Toggle ayar kartı
class InventoryToggleCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const InventoryToggleCard({
    super.key,
    required this.icon,
    this.accentColor = const Color(0xFF4F46E5),
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: value ? accentColor.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? accentColor.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value
                    ? accentColor.withValues(alpha: 0.14)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 19,
                color: value ? accentColor : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              activeColor: accentColor,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Zengin boş durum (Empty State) kartı — çıplak gri yazı yerine premium bilgilendirme sunar.
class InventoryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Color accentColor;

  const InventoryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.accentColor = const Color(0xFF4F46E5),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.16),
                        accentColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(icon, size: 32, color: accentColor),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: Icon(actionIcon ?? Icons.add_rounded, size: 18),
                    label: Text(
                      actionLabel!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

