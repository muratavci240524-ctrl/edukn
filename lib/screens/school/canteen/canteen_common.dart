import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';

/// KantiN Studio tasarım sistemi: renkler, tipografi, giriş alanları,
/// sanal kantin kartı ve ortak modallar (`AlertDialog` yerine `CnDialogShell`).
class CnColors {
  // Marka renkleri (Figma KantiN kimliği)
  static const Color brand = Color(0xFFE11D48); // Rose-600
  static const Color brandDark = Color(0xFFBE123C); // Rose-700
  static const Color brandLight = Color(0xFFFB7185); // Rose-400
  static const Color pink = Color(0xFFFFE4E6); // Rose-100
  static const Color pinkBg = Color(0xFFFFF1F2); // Rose-50

  // Nötr stüdyo yüzeyleri
  static const Color bg = Color(0xFFF8FAFC); // Slate-50
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0); // Slate-200
  static const Color borderStrong = Color(0xFFCBD5E1); // Slate-300

  // Metin renkleri
  static const Color text = Color(0xFF0F172A); // Slate-900
  static const Color slate = Color(0xFF475569); // Slate-600
  static const Color muted = Color(0xFF64748B); // Slate-500

  // Durum renkleri
  static const Color ok = Color(0xFF10B981); // Emerald-500
  static const Color okDark = Color(0xFF059669); // Emerald-600
  static const Color okSoft = Color(0xFFECFDF5);
  static const Color warn = Color(0xFFF59E0B); // Amber-500
  static const Color warnDark = Color(0xFFD97706);
  static const Color warnSoft = Color(0xFFFFFBEB);
  static const Color indigo = Color(0xFF4F46E5); // Indigo-600
  static const Color indigoSoft = Color(0xFFEEF2FF);

  static const LinearGradient gradient = LinearGradient(
    colors: [Color(0xFFE11D48), Color(0xFFFB7185)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF9F1239), Color(0xFFE11D48), Color(0xFFFB7185)],
    stops: [0.0, 0.55, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient passiveCardGradient = LinearGradient(
    colors: [Color(0xFF334155), Color(0xFF64748B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

const List<String> kCnPresetCategories = [
  'Tost & Sandviç',
  'İçecek',
  'Atıştırmalık',
  'Unlu Mamul',
  'Süt Ürünleri',
  'Meyve & Sağlıklı',
  'Çikolata & Tatlı',
  'Kırtasiye',
];

const List<String> kCnProductUnits = ['adet', 'paket', 'porsiyon', 'lt', 'kg'];

final NumberFormat _moneyFmt = NumberFormat('#,##0.00', 'tr_TR');
final DateFormat _dateFmt = DateFormat('dd.MM.yyyy');
final DateFormat _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

String cnMoney(num v) => '${_moneyFmt.format(v)} ₺';
String cnDate(DateTime? d) => d == null ? '-' : _dateFmt.format(d);
String cnDateTime(DateTime? d) => d == null ? '-' : _dateTimeFmt.format(d);

double cnParseMoney(String s) =>
    double.tryParse(s.trim().replaceAll('.', '').replaceAll(',', '.')) ??
    double.tryParse(s.trim().replaceAll(',', '.')) ??
    0;

/// Kullanıcı dostu Türkçe hata dönüştürücü.
String cnErr(Object e) {
  if (e is CanteenException) return e.message;
  final raw = e.toString();
  final low = raw.toLowerCase();
  if (low.contains('permission-denied') ||
      low.contains('missing or insufficient permissions')) {
    return 'Yetki hatası: Firestore kuralları henüz yayınlanmamış olabilir (firebase deploy --only firestore:rules,storage).';
  }
  if (low.contains('unavailable') || low.contains('network')) {
    return 'Bağlantı hatası: İnternet bağlantınızı kontrol edip tekrar deneyin.';
  }
  if (low.contains('not-found')) {
    return 'İstenen kayıt bulunamadı.';
  }
  return 'Beklenmeyen hata: $raw';
}

String cnMethodLabel(String m) {
  switch (m) {
    case 'card':
      return 'Kantin Kartı';
    case 'mobile':
      return 'Mobil Ödeme';
    case 'qr':
      return 'Mobil / QR';
    case 'pos':
      return 'POS (Kredi/Banka Kartı)';
    case 'cash':
      return 'Nakit';
    case 'online':
      return 'Online Yükleme';
    default:
      return m;
  }
}

IconData cnMethodIcon(String m) {
  switch (m) {
    case 'card':
      return Icons.contactless_rounded;
    case 'mobile':
    case 'qr':
      return Icons.qr_code_scanner_rounded;
    case 'pos':
      return Icons.credit_card_rounded;
    case 'cash':
      return Icons.payments_outlined;
    case 'online':
      return Icons.language_rounded;
    default:
      return Icons.receipt_long_outlined;
  }
}

IconData cnCategoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('tost') || c.contains('sandviç') || c.contains('sandvic')) {
    return Icons.lunch_dining_rounded;
  }
  if (c.contains('içecek') ||
      c.contains('icecek') ||
      c.contains('su') ||
      c.contains('ayran')) {
    return Icons.local_drink_rounded;
  }
  if (c.contains('atıştırma') || c.contains('cips') || c.contains('kraker')) {
    return Icons.cookie_outlined;
  }
  if (c.contains('unlu') || c.contains('poğaça') || c.contains('simit')) {
    return Icons.bakery_dining_rounded;
  }
  if (c.contains('süt') || c.contains('yoğurt')) {
    return Icons.icecream_outlined;
  }
  if (c.contains('meyve') || c.contains('sağlık') || c.contains('salata')) {
    return Icons.eco_rounded;
  }
  if (c.contains('çikolata') || c.contains('tatlı') || c.contains('gofret')) {
    return Icons.cake_outlined;
  }
  if (c.contains('kırtasiye') || c.contains('kalem')) {
    return Icons.edit_note_rounded;
  }
  return Icons.fastfood_rounded;
}

Color cnCategoryColor(String category) {
  final c = category.toLowerCase();
  if (c.contains('tost') || c.contains('sandviç') || c.contains('sandvic')) {
    return const Color(0xFFEA580C);
  }
  if (c.contains('içecek') || c.contains('icecek') || c.contains('su')) {
    return const Color(0xFF0284C7);
  }
  if (c.contains('atıştırma') || c.contains('cips')) {
    return const Color(0xFFD97706);
  }
  if (c.contains('unlu') || c.contains('poğaça') || c.contains('simit')) {
    return const Color(0xFFB45309);
  }
  if (c.contains('süt')) {
    return const Color(0xFF2563EB);
  }
  if (c.contains('meyve') || c.contains('sağlık')) {
    return const Color(0xFF059669);
  }
  if (c.contains('çikolata') || c.contains('tatlı')) {
    return const Color(0xFF9333EA);
  }
  if (c.contains('kırtasiye')) {
    return const Color(0xFF4F46E5);
  }
  return CnColors.brand;
}

String cnFormatCardNo(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return 'KNT-000000';
  return s;
}

String cnInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Ö';
  String firstChar(String s) => String.fromCharCode(s.runes.first);
  if (parts.length == 1) return firstChar(parts.first).toUpperCase();
  return (firstChar(parts.first) + firstChar(parts.last)).toUpperCase();
}

void cnSnack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: error ? CnColors.brandDark : CnColors.okDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
    ),
  );
}

/// Global `lib/main.dart` `InputDecorationTheme(border: BorderSide.none)`
/// tuzağını tamamen ezen net çerçeveli form alanı dekorasyonu.
InputDecoration cnInput(
  String label, {
  String? hint,
  Widget? prefix,
  Widget? suffix,
  String? helper,
  Color? fillColor,
  EdgeInsets? contentPadding,
}) {
  OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label.isEmpty ? null : label,
    hintText: hint,
    helperText: helper,
    prefixIcon: prefix,
    suffixIcon: suffix,
    isDense: true,
    filled: true,
    fillColor: fillColor ?? CnColors.surfaceAlt,
    labelStyle: const TextStyle(
      color: CnColors.slate,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
    ),
    floatingLabelStyle: const TextStyle(
      color: CnColors.brand,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
    ),
    helperStyle: const TextStyle(color: CnColors.muted, fontSize: 11.5),
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: b(CnColors.border),
    enabledBorder: b(CnColors.border),
    disabledBorder: b(const Color(0xFFE2E8F0)),
    focusedBorder: b(CnColors.brand, 1.6),
    errorBorder: b(Colors.red.shade400),
    focusedErrorBorder: b(Colors.red.shade600, 1.6),
  );
}

ButtonStyle cnPrimaryBtn({EdgeInsets? padding, Color? backgroundColor}) =>
    ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? CnColors.brand,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFE2E8F0),
      disabledForegroundColor: const Color(0xFF94A3B8),
      elevation: 0,
      shadowColor: Colors.transparent,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      minimumSize: const Size(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

ButtonStyle cnOutlineBtn({
  EdgeInsets? padding,
  Color? color,
}) => OutlinedButton.styleFrom(
  foregroundColor: color ?? CnColors.brand,
  backgroundColor: Colors.white,
  side: BorderSide(color: (color ?? CnColors.brand).withValues(alpha: 0.35)),
  elevation: 0,
  padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  minimumSize: const Size(0, 42),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

ButtonStyle cnGhostBtn({EdgeInsets? padding}) => TextButton.styleFrom(
  foregroundColor: CnColors.slate,
  padding: padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
  minimumSize: const Size(0, 40),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

ButtonStyle cnTextBtn() => TextButton.styleFrom(
  foregroundColor: CnColors.brand,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  minimumSize: const Size(0, 36),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
);

/// Temiz beyaz stüdyo kartı.
class CnPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const CnPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? CnColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Bölüm alt başlığı (modal ve formlar için).
class CnSectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Widget? trailing;

  const CnSectionLabel(this.text, {super.key, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: CnColors.brand),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: CnColors.slate,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Küçük durum/etiket rozeti.
class CnBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const CnBadge(
    this.label, {
    super.key,
    this.color = CnColors.brand,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CnEmpty extends StatelessWidget {
  final String text;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  const CnEmpty(
    this.text, {
    super.key,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: CnColors.pinkBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: CnColors.pink),
              ),
              child: Icon(icon, size: 28, color: CnColors.brand),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CnColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CnColors.muted, fontSize: 12.5),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

class CnError extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const CnError(this.text, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => CnEmpty(
    'Veri yüklenemedi',
    subtitle: text,
    icon: Icons.gpp_maybe_outlined,
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            style: cnOutlineBtn(),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Tekrar Dene'),
          ),
  );
}

class CnKpi extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const CnKpi({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.subtitle,
    this.color = CnColors.brand,
  });

  @override
  Widget build(BuildContext context) {
    return CnPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CnColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: CnColors.text,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: CnColors.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ürün görseli: `imageUrl` varsa ağdan yükler, yoksa renkli kategori ikonu gösterir.
class CnProductAvatar extends StatelessWidget {
  final String imageUrl;
  final String category;
  final double width;
  final double height;
  final double radius;

  const CnProductAvatar({
    super.key,
    required this.imageUrl,
    required this.category,
    this.width = 52,
    this.height = 52,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final col = cnCategoryColor(category);
    final icon = cnCategoryIcon(category);

    Widget fallback() {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [col.withValues(alpha: 0.16), col.withValues(alpha: 0.06)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: col.withValues(alpha: 0.18)),
        ),
        child: Center(
          child: Icon(
            icon,
            color: col,
            size: (height * 0.44).clamp(18.0, 34.0),
          ),
        ),
      );
    }

    final url = imageUrl.trim();
    if (url.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: width,
              height: height,
              color: CnColors.surfaceAlt,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CnColors.brand,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Figma KantiN tasarımından esinlenen parlak sanal kantin kartı.
class CnVirtualCard extends StatelessWidget {
  final CanteenCard card;
  final double? spentToday;
  final bool compact;
  final Widget? trailingAction;

  const CnVirtualCard({
    super.key,
    required this.card,
    this.spentToday,
    this.compact = false,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final active = card.isActive;
    final hasLimit = card.dailyLimit > 0;
    final spent = (spentToday ?? 0).clamp(0.0, double.infinity);
    final remaining = hasLimit
        ? (card.dailyLimit - spent).clamp(0.0, card.dailyLimit)
        : 0.0;
    final progress = hasLimit
        ? (remaining / card.dailyLimit).clamp(0.0, 1.0)
        : 1.0;

    return Container(
      decoration: BoxDecoration(
        gradient: active ? CnColors.cardGradient : CnColors.passiveCardGradient,
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        boxShadow: [
          BoxShadow(
            color: (active ? CnColors.brand : CnColors.slate).withValues(
              alpha: 0.24,
            ),
            blurRadius: compact ? 14 : 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
        child: Stack(
          children: [
            // Parlak dairesel KantiN arka plan süslemeleri
            Positioned(
              right: -34,
              top: -34,
              child: Container(
                width: compact ? 120 : 165,
                height: compact ? 120 : 165,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 26,
              bottom: -48,
              child: Container(
                width: compact ? 95 : 135,
                height: compact ? 95 : 135,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: compact ? 38 : 48,
              child: IgnorePointer(
                child: Text(
                  'KN',
                  style: TextStyle(
                    fontSize: compact ? 42 : 60,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -3,
                    color: Colors.white.withValues(alpha: 0.11),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Üst satır: KantiN marka + NFC + Durum rozeti
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.contactless_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'KantiN Kart',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.28)
                                : Colors.black.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                            ),
                          ),
                          child: Text(
                            active ? 'AKTİF' : 'PASİF',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (trailingAction != null)
                          trailingAction!
                        else
                          Container(
                            width: 30,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Icon(
                              Icons.sim_card_outlined,
                              size: 15,
                              color: Colors.brown.shade800,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    Text(
                      'CÜZDAN BAKİYESİ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.white.withValues(alpha: 0.80),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        cnMoney(card.balance),
                        style: TextStyle(
                          fontSize: compact ? 24 : 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.studentName.trim().isEmpty
                                    ? 'Öğrenci Seçilmedi'
                                    : card.studentName.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 14 : 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (card.className.trim().isNotEmpty)
                                    card.className.trim(),
                                  cnFormatCardNo(card.cardNo),
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!hasLimit)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Limitsiz',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (hasLimit) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              spentToday != null
                                  ? 'Günlük Kalan: ${cnMoney(remaining)}'
                                  : 'Günlük Limit: ${cnMoney(card.dailyLimit)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                          if (spentToday != null)
                            Text(
                              '/ ${cnMoney(card.dailyLimit)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: Colors.black.withValues(alpha: 0.22),
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Material 3 `AlertDialog` (`#ECE6F0` lavanta-gri) tuzağını tamamen ortadan kaldıran
/// bembeyaz, net başlıklı ve sabit alt çubuklu modern KantiN modal kabuğu.
class CnDialogShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final double maxWidth;
  final Widget child;
  final bool scrollable;
  final String? errorText;
  final String cancelLabel;
  final bool showCancel;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final Color? primaryColor;
  final bool loading;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;

  const CnDialogShell({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.credit_card_rounded,
    this.iconColor = CnColors.brand,
    this.maxWidth = 600,
    required this.child,
    this.scrollable = true,
    this.errorText,
    this.cancelLabel = 'Vazgeç',
    this.showCancel = true,
    this.primaryLabel,
    this.primaryIcon,
    this.primaryColor,
    this.loading = false,
    this.onPrimary,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = (mq.size.height - mq.viewInsets.bottom - 32).clamp(
      280.0,
      820.0,
    );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.22),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxH),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst Başlık
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Icon(icon, color: iconColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: CnColors.text,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: CnColors.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: loading
                          ? null
                          : (onCancel ?? () => Navigator.pop(context)),
                      style: IconButton.styleFrom(
                        backgroundColor: CnColors.surfaceAlt,
                        foregroundColor: CnColors.slate,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),

              // Gövde
              Flexible(
                child: scrollable
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                        child: child,
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: child,
                      ),
              ),

              // Hata Bandı
              if (errorText != null && errorText!.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: CnColors.pinkBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: CnColors.brandDark,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorText!,
                          style: const TextStyle(
                            color: CnColors.brandDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Alt Çubuk
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                decoration: const BoxDecoration(
                  color: CnColors.surfaceAlt,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (showCancel)
                      TextButton(
                        style: cnGhostBtn(),
                        onPressed: loading
                            ? null
                            : (onCancel ?? () => Navigator.pop(context)),
                        child: Text(cancelLabel),
                      ),
                    if (primaryLabel != null)
                      ElevatedButton.icon(
                        style: cnPrimaryBtn(backgroundColor: primaryColor),
                        onPressed: loading ? null : onPrimary,
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                primaryIcon ?? Icons.check_rounded,
                                size: 18,
                              ),
                        label: Text(primaryLabel!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarih aralığı seçici.
Future<DateTimeRange?> cnPickRange(
  BuildContext context,
  DateTimeRange current,
) {
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 366)),
    initialDateRange: current,
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: CnColors.brand,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: CnColors.text,
          ),
        ),
        child: child!,
      );
    },
  );
}

DateTime cnStartOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime cnEndOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// `AlertDialog` kullanmayan şık onay penceresi.
Future<bool> cnConfirm(
  BuildContext context,
  String title,
  String message, {
  String confirmLabel = 'Onayla',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => CnDialogShell(
      title: title,
      icon: icon,
      iconColor: danger ? Colors.red.shade600 : CnColors.brand,
      maxWidth: 440,
      primaryLabel: confirmLabel,
      primaryColor: danger ? Colors.red.shade600 : CnColors.brand,
      onCancel: () => Navigator.pop(ctx, false),
      onPrimary: () => Navigator.pop(ctx, true),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          color: CnColors.slate,
          height: 1.45,
        ),
      ),
    ),
  );
  return r == true;
}
