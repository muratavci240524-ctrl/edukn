import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/canteen/canteen_models.dart';
import '../../services/canteen_service.dart';
import '../../services/payment_gateway_service.dart';

/// Kantin veli ve öğrenci ekranları için paylaşılan renkler, formatlayıcılar,
/// kategori stilleri ve ortak görsel bileşenler.
const Color kCanteenRed = Color(0xFFE5173F);
const Color kCanteenRedLight = Color(0xFFFF4D6D);
const Color kCanteenRedDark = Color(0xFFB80D2E);
const Color kCanteenRedSoft = Color(0xFFFFE4EA);

const Color kCanteenEmerald = Color(0xFF2E9E5B);
const Color kCanteenEmeraldLight = Color(0xFF4ADE80);
const Color kCanteenEmeraldDark = Color(0xFF1E7E45);
const Color kCanteenEmeraldSoft = Color(0xFFDCFCE7);

const Color kCanteenOrange = Color(0xFFF97316);
const Color kCanteenAmber = Color(0xFFF59E0B);
const Color kCanteenDarkCard = Color(0xFF2B2F36);
const Color kCanteenBg = Color(0xFFF5F6FA);
const double kCanteenMaxWidth = 760;

final NumberFormat _moneyFmt = NumberFormat('#,##0.00', 'tr_TR');
final DateFormat _dateFmt = DateFormat('dd.MM.yyyy • HH:mm');

String canteenMoney(num v) => '${_moneyFmt.format(v)} ₺';

String canteenDate(DateTime? d) => d == null ? '-' : _dateFmt.format(d);

String canteenDateTime(DateTime? d) => canteenDate(d);

String canteenTrLower(String input) => input
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .replaceAll('Ğ', 'ğ')
    .replaceAll('Ü', 'ü')
    .replaceAll('Ş', 'ş')
    .replaceAll('Ö', 'ö')
    .replaceAll('Ç', 'ç')
    .toLowerCase();

/// İçeriği geniş ekranlarda [kCanteenMaxWidth] ile ortalamak için yan boşluk.
double canteenSidePad(double width) {
  final p = (width - kCanteenMaxWidth) / 2;
  return p < 16 ? 16 : p;
}

InputDecoration canteenInputDecoration({
  String? hint,
  String? label,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  Color fillColor = const Color(0xFFF8FAFC),
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
  );
  return InputDecoration(
    hintText: hint,
    labelText: label,
    hintStyle: const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
    ),
    labelStyle: const TextStyle(
      color: Color(0xFF64748B),
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    suffixText: suffixText,
    suffixStyle: const TextStyle(
      color: Color(0xFF334155),
      fontWeight: FontWeight.w800,
      fontSize: 14,
    ),
    isDense: true,
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border,
    enabledBorder: border,
    disabledBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFFF1F5F9)),
    ),
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: kCanteenRed, width: 1.6),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
    ),
  );
}

ButtonStyle canteenFilledStyle({
  Color color = kCanteenRed,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 13,
  ),
  double radius = 14,
}) => FilledButton.styleFrom(
  backgroundColor: color,
  foregroundColor: Colors.white,
  disabledBackgroundColor: color.withValues(alpha: 0.45),
  disabledForegroundColor: Colors.white,
  elevation: 0,
  padding: padding,
  minimumSize: const Size(0, 44),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
);

ButtonStyle canteenOutlinedStyle({
  Color color = const Color(0xFF334155),
  Color borderColor = const Color(0xFFCBD5E1),
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  ),
  double radius = 14,
}) => OutlinedButton.styleFrom(
  foregroundColor: color,
  backgroundColor: Colors.white,
  side: BorderSide(color: borderColor, width: 1.2),
  padding: padding,
  minimumSize: const Size(0, 44),
  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
);

void canteenSnack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: error ? const Color(0xFFDC2626) : kCanteenEmerald,
      ),
    );
}

String canteenErrorText(Object e) {
  if (e is PaymentException) return e.message;
  if (e is CanteenException) return e.message;
  final s = e.toString();
  if (s.contains('permission-denied')) {
    return 'Yetki hatası: Firestore kuralları henüz yayınlanmamış olabilir.';
  }
  return s.replaceFirst('Exception: ', '');
}

String canteenMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'online':
      return 'Online (iyzico)';
    case 'card':
      return 'Kantin Kartı';
    case 'qr':
    case 'mobile':
      return 'Mobil QR';
    case 'pos':
      return 'POS (Kredi/Banka Kartı)';
    case 'cash':
      return 'Kasa (Nakit)';
    default:
      return method.isEmpty ? 'Kart' : method;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KATEGORİ STİL VE VARSAYILAN KATEGORİ SETİ (Figma Renkli İkonlar)
// ═══════════════════════════════════════════════════════════════════════════

class CanteenCategoryStyle {
  final String name;
  final Color color;
  final IconData icon;

  const CanteenCategoryStyle({
    required this.name,
    required this.color,
    required this.icon,
  });
}

const List<CanteenCategoryStyle> kFigmaPresetCategories = [
  CanteenCategoryStyle(
    name: 'İçecek',
    color: Color(0xFF0EA5E9),
    icon: Icons.local_drink_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Tost & Sandviç',
    color: Color(0xFFF97316),
    icon: Icons.lunch_dining_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Atıştırmalık',
    color: Color(0xFF8B5CF6),
    icon: Icons.cookie_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Çikolata & Tatlı',
    color: Color(0xFFEC4899),
    icon: Icons.cake_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Unlu Mamul',
    color: Color(0xFFF59E0B),
    icon: Icons.bakery_dining_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Süt Ürünleri',
    color: Color(0xFF14B8A6),
    icon: Icons.icecream_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Meyve & Sağlıklı',
    color: Color(0xFF22C55E),
    icon: Icons.eco_rounded,
  ),
  CanteenCategoryStyle(
    name: 'Kırtasiye',
    color: Color(0xFF6366F1),
    icon: Icons.edit_note_rounded,
  ),
];

const List<Color> _fallbackPalette = [
  Color(0xFF0EA5E9),
  Color(0xFFF97316),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFF59E0B),
  Color(0xFF14B8A6),
  Color(0xFF22C55E),
  Color(0xFF6366F1),
];

CanteenCategoryStyle canteenCategoryStyle(String rawName) {
  final name = rawName.trim();
  final low = canteenTrLower(name);
  for (final preset in kFigmaPresetCategories) {
    if (canteenTrLower(preset.name) == low) {
      return CanteenCategoryStyle(
        name: name,
        color: preset.color,
        icon: preset.icon,
      );
    }
  }
  if (low.contains('içecek') || low.contains('su') || low.contains('ayran')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFF0EA5E9),
      icon: Icons.local_drink_rounded,
    );
  }
  if (low.contains('tost') ||
      low.contains('sandviç') ||
      low.contains('sandvic') ||
      low.contains('yemek')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFFF97316),
      icon: Icons.lunch_dining_rounded,
    );
  }
  if (low.contains('çikolata') ||
      low.contains('cikolata') ||
      low.contains('tatlı') ||
      low.contains('tatli') ||
      low.contains('gofret')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFFEC4899),
      icon: Icons.cake_rounded,
    );
  }
  if (low.contains('atıştır') ||
      low.contains('atistir') ||
      low.contains('bisküvi') ||
      low.contains('cips') ||
      low.contains('kraker')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFF8B5CF6),
      icon: Icons.cookie_rounded,
    );
  }
  if (low.contains('unlu') ||
      low.contains('poğaça') ||
      low.contains('pogaca') ||
      low.contains('simit') ||
      low.contains('börek')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFFF59E0B),
      icon: Icons.bakery_dining_rounded,
    );
  }
  if (low.contains('süt') || low.contains('sut') || low.contains('dondurma')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFF14B8A6),
      icon: Icons.icecream_rounded,
    );
  }
  if (low.contains('meyve') ||
      low.contains('sağlık') ||
      low.contains('saglik') ||
      low.contains('kuruyemiş')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFF22C55E),
      icon: Icons.eco_rounded,
    );
  }
  if (low.contains('kırtasiye') || low.contains('kirtasiye')) {
    return CanteenCategoryStyle(
      name: name,
      color: const Color(0xFF6366F1),
      icon: Icons.edit_note_rounded,
    );
  }
  final hash = low.codeUnits.fold<int>(0, (a, b) => a + b);
  return CanteenCategoryStyle(
    name: name.isEmpty ? 'Diğer' : name,
    color: _fallbackPalette[hash % _fallbackPalette.length],
    icon: Icons.category_rounded,
  );
}

/// Figma'daki 8 temel kategoriyi veritabanındaki dinamik ürün kategorileriyle
/// ve karttaki mevcut blokeli kategorilerle tekilleştirerek birleştirir.
List<String> mergeCanteenCategories(
  Iterable<String> dynamicCategories,
  Iterable<String> blockedCategories,
) {
  final exactByLower = <String, String>{};
  for (final c in [...dynamicCategories, ...blockedCategories]) {
    final trimmed = c.trim();
    if (trimmed.isEmpty) continue;
    exactByLower.putIfAbsent(canteenTrLower(trimmed), () => trimmed);
  }

  final usedLower = <String>{};
  final merged = <String>[];

  for (final preset in kFigmaPresetCategories) {
    final low = canteenTrLower(preset.name);
    usedLower.add(low);
    merged.add(exactByLower[low] ?? preset.name);
  }

  final extras = <String>[];
  for (final entry in exactByLower.entries) {
    if (usedLower.add(entry.key)) {
      extras.add(entry.value);
    }
  }
  extras.sort((a, b) => canteenTrLower(a).compareTo(canteenTrLower(b)));
  merged.addAll(extras);
  return merged;
}

// ═══════════════════════════════════════════════════════════════════════════
// VERİ BESLEMESİ (ürünler + seçili kartın işlemleri + bugünkü harcama)
// ═══════════════════════════════════════════════════════════════════════════

class CanteenFeed extends ChangeNotifier {
  final String instId;
  List<CanteenProduct> products = const [];
  bool productsLoading = true;
  Object? productsError;

  List<CanteenTransaction> txs = const [];
  bool txLoading = true;
  Object? txError;
  double todaySpent = 0;

  StreamSubscription<List<CanteenProduct>>? _pSub;
  StreamSubscription<List<CanteenTransaction>>? _tSub;
  String? _cardNo;
  bool _disposed = false;

  CanteenFeed(this.instId) {
    _pSub = CanteenService.instance
        .watchProducts(instId)
        .listen(
          (l) {
            products = l.where((p) => p.isActive).toList();
            productsLoading = false;
            productsError = null;
            _notify();
          },
          onError: (Object e) {
            productsLoading = false;
            productsError = e;
            _notify();
          },
        );
  }

  List<String> get categories {
    final set = <String>{
      for (final p in products)
        if (p.category.trim().isNotEmpty) p.category.trim(),
    };
    return set.toList()
      ..sort((a, b) => canteenTrLower(a).compareTo(canteenTrLower(b)));
  }

  void bindCard(String? cardNo) {
    if (cardNo == _cardNo) return;
    _cardNo = cardNo;
    _tSub?.cancel();
    _tSub = null;
    txs = const [];
    todaySpent = 0;
    txError = null;
    if (cardNo == null || cardNo.isEmpty) {
      txLoading = false;
      _notify();
      return;
    }
    txLoading = true;
    _notify();
    _tSub = CanteenService.instance
        .watchTransactions(instId, cardNo: cardNo, limit: 0)
        .listen(
          (l) {
            txs = l;
            txLoading = false;
            txError = null;
            _notify();
            _refreshToday(cardNo);
          },
          onError: (Object e) {
            txLoading = false;
            txError = e;
            _notify();
          },
        );
  }

  void _refreshToday(String cardNo) {
    CanteenService.instance
        .todaySpent(instId, cardNo)
        .then((v) {
          if (_disposed || cardNo != _cardNo) return;
          todaySpent = v;
          _notify();
        })
        .catchError((Object _) {});
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pSub?.cancel();
    _tSub?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ÜRÜN FİLTRE MODELİ
// ═══════════════════════════════════════════════════════════════════════════

class CanteenProductFilterModel extends ChangeNotifier {
  final TextEditingController search = TextEditingController();
  String category = 'Tümü';
  int priceBand = 0;
  bool inStockOnly = false;

  static const List<String> bands = ['Tümü', '0-25 ₺', '25-50 ₺', '50+ ₺'];

  CanteenProductFilterModel() {
    search.addListener(notifyListeners);
  }

  void setCategory(String v) {
    category = v;
    notifyListeners();
  }

  void setBand(int v) {
    priceBand = v;
    notifyListeners();
  }

  void setInStock(bool v) {
    inStockOnly = v;
    notifyListeners();
  }

  void clearSearch() {
    search.clear();
  }

  List<CanteenProduct> apply(List<CanteenProduct> all) {
    final q = canteenTrLower(search.text.trim());
    final selectedLow = canteenTrLower(category.trim());
    return all.where((p) {
      if (q.isNotEmpty &&
          !canteenTrLower(p.name).contains(q) &&
          !canteenTrLower(p.category).contains(q)) {
        return false;
      }
      if (category != 'Tümü' &&
          canteenTrLower(p.category.trim()) != selectedLow) {
        return false;
      }
      if (inStockOnly && p.stock <= 0) return false;
      switch (priceBand) {
        case 1:
          if (p.price >= 25) return false;
        case 2:
          if (p.price < 25 || p.price >= 50) return false;
        case 3:
          if (p.price < 50) return false;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FIGMA KANTİN HERO BAŞLIK + İKİLİ YÜZEN ÖZET KARTI
// ═══════════════════════════════════════════════════════════════════════════

class _HeaderWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 26)
      ..quadraticBezierTo(w * 0.25, h + 6, w * 0.52, h - 12)
      ..quadraticBezierTo(w * 0.80, h - 30, w, h - 10)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _KnWatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Yumuşak dekoratif ışık halkaları
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.12),
      95,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.78),
      75,
      glowPaint,
    );

    // Merkezde geometrik "K N" filigranı (Figma kart tasarımı)
    final markPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.11)
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height * 0.48;
    const h = 86.0;
    const barW = 11.0;

    // Sol "K" geometrisi
    final kLeft = cx - 78;
    final kTop = cy - h / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(kLeft, kTop, barW, h),
        const Radius.circular(3),
      ),
      markPaint,
    );
    final kUpper = Path()
      ..moveTo(kLeft + barW + 5, cy - 3)
      ..lineTo(kLeft + 44, kTop)
      ..lineTo(kLeft + 56, kTop)
      ..lineTo(kLeft + barW + 17, cy + 2)
      ..close();
    canvas.drawPath(kUpper, markPaint);

    final kLower = Path()
      ..moveTo(kLeft + barW + 5, cy + 3)
      ..lineTo(kLeft + barW + 17, cy - 2)
      ..lineTo(kLeft + 56, kTop + h)
      ..lineTo(kLeft + 44, kTop + h)
      ..close();
    canvas.drawPath(kLower, markPaint);

    // Sağ "N" geometrisi
    final nLeft = cx + 22;
    final nTop = cy - h / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(nLeft, nTop, barW, h),
        const Radius.circular(3),
      ),
      markPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(nLeft + 45, nTop, barW, h),
        const Radius.circular(3),
      ),
      markPaint,
    );
    final nDiag = Path()
      ..moveTo(nLeft + barW + 2, nTop)
      ..lineTo(nLeft + barW + 14, nTop)
      ..lineTo(nLeft + 43, nTop + h)
      ..lineTo(nLeft + 31, nTop + h)
      ..close();
    canvas.drawPath(nDiag, markPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CanteenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String className;
  final CanteenCard? card;
  final double todaySpent;
  final bool loading;
  final double sidePad;
  final bool emeraldTheme;
  final VoidCallback? onBack;
  final Widget? trailing;

  const CanteenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.className = '',
    required this.card,
    this.todaySpent = 0,
    required this.loading,
    required this.sidePad,
    this.emeraldTheme = false,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final gradientColors = emeraldTheme
        ? const [Color(0xFF238649), kCanteenEmerald, kCanteenEmeraldLight]
        : const [Color(0xFFD61137), kCanteenRed, kCanteenRedLight];

    return Stack(
      children: [
        Positioned.fill(
          bottom: 36,
          child: ClipPath(
            clipper: _HeaderWaveClipper(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  stops: const [0.0, 0.58, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CustomPaint(painter: _KnWatermarkPainter()),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 12),
            child: Column(
              children: [
                // Üst Gezinme Çubuğu
                Row(
                  children: [
                    if (onBack != null)
                      Material(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onBack,
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            subtitle.isNotEmpty ? subtitle : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (className.trim().isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: Text(
                                    '•',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      className.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    trailing ?? const SizedBox(width: 38, height: 38),
                  ],
                ),
                const SizedBox(height: 18),
                // Merkez Bakiye Göstergesi
                Text(
                  emeraldTheme ? 'Kart Bakiyesi • Yüklemeler' : 'Güncel Bakiye',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.8,
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              canteenMoney(card?.balance ?? 0),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                  ),
                ),
                if (card != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _HeaderPill(
                        icon: Icons.credit_card_rounded,
                        label: 'Kart: ${card!.cardNo}',
                      ),
                      _HeaderPill(
                        icon: card!.isActive
                            ? Icons.check_circle_rounded
                            : Icons.pause_circle_filled_rounded,
                        label: card!.isActive ? 'Aktif' : 'Pasif',
                        bgColor: card!.isActive
                            ? Colors.black.withValues(alpha: 0.22)
                            : Colors.black.withValues(alpha: 0.45),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                // Yüzen Beyaz İkili Özet Kartı (Bugün Harcanan & Günlük Limit)
                _FloatingDualSummaryCard(
                  todaySpent: todaySpent,
                  dailyLimit: card?.dailyLimit ?? 0,
                  hasCard: card != null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? bgColor;

  const _HeaderPill({required this.icon, required this.label, this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingDualSummaryCard extends StatelessWidget {
  final double todaySpent;
  final double dailyLimit;
  final bool hasCard;

  const _FloatingDualSummaryCard({
    required this.todaySpent,
    required this.dailyLimit,
    required this.hasCard,
  });

  @override
  Widget build(BuildContext context) {
    final spentZero = todaySpent <= 0.001;
    final spentColor = spentZero ? kCanteenEmerald : kCanteenRed;
    final spentSoft = spentZero ? kCanteenEmeraldSoft : kCanteenRedSoft;

    final limitText = !hasCard
        ? '-'
        : (dailyLimit <= 0 ? 'Limitsiz' : canteenMoney(dailyLimit));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDF2F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F172A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: spentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shopping_bag_rounded,
                      color: spentColor,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Bugün Harcanan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            hasCard ? canteenMoney(todaySpent) : '-',
                            style: TextStyle(
                              color: spentColor,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              color: const Color(0xFFE2E8F0),
            ),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF7ED),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.speed_rounded,
                      color: kCanteenOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Günlük Limit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            limitText,
                            style: const TextStyle(
                              color: Color(0xFFEA580C),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ORTAK KART, HIZLI AKSİYON VE SEKME BİLEŞENLERİ
// ═══════════════════════════════════════════════════════════════════════════

class CanteenSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;

  const CanteenSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.accentColor = kCanteenRed,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDF2F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accentColor, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class CanteenQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const CanteenQuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.color = kCanteenRed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDF2F7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CanteenTabBar extends StatelessWidget {
  final List<String> labels;
  final int index;
  final bool emeraldActive;
  final ValueChanged<int> onChanged;

  const CanteenTabBar({
    super.key,
    required this.labels,
    required this.index,
    this.emeraldActive = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = emeraldActive ? kCanteenEmerald : kCanteenRed;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: i == index ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: i == index
                              ? Colors.white
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CanteenMessageBox extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool error;

  const CanteenMessageBox({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = error ? const Color(0xFFDC2626) : const Color(0xFF64748B);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: error ? const Color(0xFFFECACA) : const Color(0xFFEDF2F7),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: tone),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: error ? const Color(0xFFB91C1C) : const Color(0xFF475569),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kart Kullanım Durumu (Aktif / Pasif) kartı.
class CanteenCardStatusCard extends StatelessWidget {
  final bool isActive;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const CanteenCardStatusCard({
    super.key,
    required this.isActive,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final shieldBg = isActive ? kCanteenEmeraldSoft : const Color(0xFFF1F5F9);
    final shieldFg = isActive ? kCanteenEmerald : const Color(0xFF64748B);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDF2F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: shieldBg, shape: BoxShape.circle),
            child: Icon(
              isActive ? Icons.verified_user_rounded : Icons.shield_outlined,
              color: shieldFg,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kart Kullanım Durumu (Aktif / Pasif)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isActive
                      ? 'Kart kullanıma açık. Kayıp durumunda anında kapatabilirsiniz.'
                      : 'Kart pasif durumda; kantin kasasında harcama yapılamaz.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? const Color(0xFF64748B) : kCanteenRedDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: isActive,
            activeTrackColor: kCanteenRed,
            activeThumbColor: Colors.white,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// İŞLEM HAREKETLERİ (Figma Kırmızı/Yeşil Sekmeli Kartlar)
// ═══════════════════════════════════════════════════════════════════════════

/// filter: 'all' | 'sale' | 'topup'
class CanteenTransactionsSliver extends StatefulWidget {
  final CanteenFeed feed;
  final String filter;
  final ValueChanged<String> onFilter;

  const CanteenTransactionsSliver({
    super.key,
    required this.feed,
    required this.filter,
    required this.onFilter,
  });

  @override
  State<CanteenTransactionsSliver> createState() =>
      _CanteenTransactionsSliverState();
}

class _CanteenTransactionsSliverState extends State<CanteenTransactionsSliver> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _match(CanteenTransaction t) {
    switch (widget.filter) {
      case 'sale':
        if (t.type != 'sale' && t.type != 'refund') return false;
        break;
      case 'topup':
        if (t.type != 'topup') return false;
        break;
      default:
        break;
    }
    final q = canteenTrLower(_searchCtrl.text.trim());
    if (q.isEmpty) return true;
    final typeText = t.type == 'topup'
        ? 'yükleme bakiye'
        : t.type == 'refund'
        ? 'iade'
        : 'satış harcama';
    final methodText = canteenMethodLabel(t.method);
    final itemsText = t.items.map((e) => '${e.qty}x ${e.name}').join(' ');
    final dateText = canteenDateTime(t.createdAt);
    final moneyText =
        '${canteenMoney(t.amount)} ${t.amount.toStringAsFixed(2)}';
    final hay = canteenTrLower(
      '$typeText $methodText $itemsText $dateText $moneyText ${t.id}',
    );
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final list = feed.txs.where(_match).toList();
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TxFilterBar(
              selected: widget.filter,
              allCount: feed.txs.length,
              saleCount: feed.txs
                  .where((t) => t.type == 'sale' || t.type == 'refund')
                  .length,
              topupCount: feed.txs.where((t) => t.type == 'topup').length,
              onSelect: widget.onFilter,
            ),
          ),
        ),
        if (!feed.txLoading && feed.txs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: canteenInputDecoration(
                  hint:
                      'Kayıtlarda ara (ürün adı, yöntem, tarih veya tutar)...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
          ),
        if (feed.txLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: kCanteenRed),
              ),
            ),
          )
        else if (feed.txError != null)
          SliverToBoxAdapter(
            child: CanteenMessageBox(
              text:
                  'Hareketler yüklenemedi: ${canteenErrorText(feed.txError!)}',
              icon: Icons.error_outline_rounded,
              error: true,
            ),
          )
        else if (list.isEmpty)
          SliverToBoxAdapter(
            child: CanteenMessageBox(
              text: _searchCtrl.text.trim().isNotEmpty
                  ? 'Aramayla eşleşen işlem kaydı bulunamadı.'
                  : widget.filter == 'topup'
                  ? 'Henüz bakiye yükleme hareketi bulunmuyor.'
                  : widget.filter == 'sale'
                  ? 'Henüz kantin harcaması bulunmuyor.'
                  : 'Henüz işlem hareketi bulunmuyor.',
              icon: _searchCtrl.text.trim().isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.receipt_long_rounded,
            ),
          )
        else
          SliverList.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => CanteenTransactionTile(tx: list[i]),
          ),
      ],
    );
  }
}

class _TxFilterBar extends StatelessWidget {
  final String selected;
  final int allCount;
  final int saleCount;
  final int topupCount;
  final ValueChanged<String> onSelect;

  const _TxFilterBar({
    required this.selected,
    required this.allCount,
    required this.saleCount,
    required this.topupCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('all', 'Tümü ($allCount)', const Color(0xFF1E293B)),
      ('sale', 'Harcamalar ($saleCount)', kCanteenRed),
      ('topup', 'Yüklemeler ($topupCount)', kCanteenEmerald),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(item.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected == item.$1 ? item.$3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: selected == item.$1
                              ? Colors.white
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CanteenTransactionTile extends StatefulWidget {
  final CanteenTransaction tx;

  const CanteenTransactionTile({super.key, required this.tx});

  @override
  State<CanteenTransactionTile> createState() => _CanteenTransactionTileState();
}

class _CanteenTransactionTileState extends State<CanteenTransactionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final isTop = tx.type == 'topup';
    final isRefund = tx.type == 'refund';
    final positive = isTop || isRefund;

    final title = isTop
        ? 'Bakiye Yükleme'
        : isRefund
        ? 'İade İşlemi'
        : 'Kantin Harcaması';

    final iconBg = isTop
        ? kCanteenEmeraldSoft
        : isRefund
        ? const Color(0xFFCCFBF1)
        : const Color(0xFFFFF7ED);
    final iconFg = isTop
        ? kCanteenEmerald
        : isRefund
        ? const Color(0xFF0D9488)
        : kCanteenOrange;
    final iconData = isTop
        ? Icons.account_balance_wallet_rounded
        : isRefund
        ? Icons.replay_rounded
        : Icons.shopping_bag_rounded;

    final amountColor = positive ? kCanteenEmerald : kCanteenRed;
    final hasItems = tx.items.isNotEmpty;
    final summary = hasItems
        ? tx.items.map((e) => '${e.qty}x ${e.name}').join(' • ')
        : canteenMethodLabel(tx.method);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDF2F7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: hasItems ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(iconData, color: iconFg, size: 21),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (hasItems) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  _expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: const Color(0xFF64748B),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            canteenDate(tx.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              summary,
                              maxLines: _expanded ? 4 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${positive ? '+' : '-'}${canteenMoney(tx.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: amountColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Bakiye: ${canteenMoney(tx.balanceAfter)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (hasItems && _expanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Satın Alınan Ürünler',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              canteenMethodLabel(tx.method),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 12, color: Color(0xFFE2E8F0)),
                        for (final item in tx.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kCanteenRedSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${item.qty}x',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: kCanteenRed,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  canteenMoney(item.total),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
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

// ═══════════════════════════════════════════════════════════════════════════
// KANTİN ÜRÜNLERİ (Kalıcı Arama & Kategori/Fiyat/Stok Filtreli)
// ═══════════════════════════════════════════════════════════════════════════

class CanteenProductsSliver extends StatelessWidget {
  final CanteenFeed feed;
  final CanteenProductFilterModel model;
  final List<String> blockedCategories;
  final List<String> blockedProductIds;

  const CanteenProductsSliver({
    super.key,
    required this.feed,
    required this.model,
    this.blockedCategories = const [],
    this.blockedProductIds = const [],
  });

  bool _isProductBlocked(CanteenProduct p) {
    if (blockedProductIds.contains(p.id)) return true;
    final pCat = canteenTrLower(p.category.trim());
    if (pCat.isEmpty) return false;
    return blockedCategories.any((c) => canteenTrLower(c.trim()) == pCat);
  }

  @override
  Widget build(BuildContext context) {
    final list = model.apply(feed.products);
    final cats = ['Tümü', ...feed.categories];
    return SliverMainAxisGroup(
      slivers: [
        // Arama ve filtreler yükleme/boş durumlarından bağımsız olarak daima bağlı kalır.
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEDF2F7)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x080F172A),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: model.search,
                  decoration: canteenInputDecoration(
                    hint: 'Ürün veya kategori ara...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                    ),
                    suffixIcon: model.search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: model.clearSearch,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _FilterPill(
                            label: c,
                            icon: c == 'Tümü'
                                ? Icons.apps_rounded
                                : canteenCategoryStyle(c).icon,
                            activeColor: c == 'Tümü'
                                ? kCanteenRed
                                : canteenCategoryStyle(c).color,
                            selected:
                                canteenTrLower(model.category) ==
                                canteenTrLower(c),
                            onTap: () => model.setCategory(c),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (
                      var i = 0;
                      i < CanteenProductFilterModel.bands.length;
                      i++
                    )
                      _FilterPill(
                        label: CanteenProductFilterModel.bands[i],
                        activeColor: kCanteenOrange,
                        selected: model.priceBand == i,
                        compact: true,
                        onTap: () => model.setBand(i),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sadece stoktakiler',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: model.inStockOnly,
                      activeTrackColor: kCanteenRed,
                      activeThumbColor: Colors.white,
                      onChanged: model.setInStock,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (feed.productsLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: kCanteenRed),
              ),
            ),
          )
        else if (feed.productsError != null)
          SliverToBoxAdapter(
            child: CanteenMessageBox(
              text:
                  'Ürünler yüklenemedi: ${canteenErrorText(feed.productsError!)}',
              icon: Icons.error_outline_rounded,
              error: true,
            ),
          )
        else if (list.isEmpty)
          const SliverToBoxAdapter(
            child: CanteenMessageBox(
              text: 'Filtrelere uygun kantin ürünü bulunamadı.',
              icon: Icons.search_off_rounded,
            ),
          )
        else
          SliverList.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => _ProductTile(
              product: list[i],
              blocked: _isProductBlocked(list[i]),
            ),
          ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color activeColor;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    this.icon,
    required this.activeColor,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? activeColor : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 12,
            vertical: compact ? 6 : 7,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? activeColor : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : activeColor,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final CanteenProduct product;
  final bool blocked;

  const _ProductTile({required this.product, required this.blocked});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final out = p.stock <= 0;
    final low = !out && p.isLowStock;
    final catStyle = canteenCategoryStyle(p.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: blocked ? const Color(0xFFFECDD3) : const Color(0xFFEDF2F7),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 56,
              height: 56,
              child: p.imageUrl.isEmpty
                  ? _placeholder(catStyle)
                  : Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(catStyle),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: blocked
                        ? const Color(0xFF64748B)
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _badge(
                      p.category.trim().isEmpty ? 'Genel' : p.category.trim(),
                      catStyle.color,
                    ),
                    if (out)
                      _badge('Tükendi', const Color(0xFFDC2626))
                    else if (low)
                      _badge('Az Kaldı (${p.stock})', kCanteenAmber)
                    else
                      _badge('Stokta (${p.stock})', kCanteenEmerald),
                    if (blocked)
                      _badge(
                        'Veli Blokesi',
                        kCanteenRed,
                        icon: Icons.block_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: kCanteenRedSoft.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              canteenMoney(p.price),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: kCanteenRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(CanteenCategoryStyle style) => Container(
    color: style.color.withValues(alpha: 0.12),
    child: Icon(style.icon, color: style.color, size: 26),
  );

  Widget _badge(String text, Color color, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// BAKİYE YÜKLEME DİYALOĞU (iyzico Güvenli Sanal POS - PaymentGatewayService)
// ═══════════════════════════════════════════════════════════════════════════

enum _TopUpStep { selectAmount, waiting, result }

class _TopUpPreset {
  final int amount;
  final String display;
  final Color color;

  const _TopUpPreset({
    required this.amount,
    required this.display,
    required this.color,
  });
}

class CanteenTopUpDialog extends StatefulWidget {
  final String instId;
  final CanteenCard card;

  const CanteenTopUpDialog({
    super.key,
    required this.instId,
    required this.card,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String instId,
    required CanteenCard card,
  }) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CanteenTopUpDialog(instId: instId, card: card),
  );

  @override
  State<CanteenTopUpDialog> createState() => _CanteenTopUpDialogState();
}

class _CanteenTopUpDialogState extends State<CanteenTopUpDialog> {
  static const double _minAmount = 10;
  static const double _maxAmount = 5000;

  static const List<_TopUpPreset> _presets = [
    _TopUpPreset(amount: 100, display: '100 ₺', color: kCanteenRed),
    _TopUpPreset(amount: 250, display: '250 ₺', color: Color(0xFF10B981)),
    _TopUpPreset(amount: 500, display: '500 ₺', color: kCanteenAmber),
    _TopUpPreset(amount: 1000, display: '1.000 ₺', color: Color(0xFF0EA5E9)),
  ];

  final TextEditingController _amountCtrl = TextEditingController(text: '250');

  _TopUpStep _step = _TopUpStep.selectAmount;
  PaymentSession? _session;
  bool _starting = false;
  bool _checkingStatus = false;
  String? _error;
  String? _waitingHint;
  bool _resultSuccess = false;
  String? _resultMessage;
  double _paidAmount = 0;

  @override
  void dispose() {
    _session?.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _parsedAmount {
    var raw = _amountCtrl.text.trim();
    if (raw.isEmpty) return null;
    if (raw.contains(',') && raw.contains('.')) {
      raw = raw.replaceAll('.', '').replaceAll(',', '.');
    } else {
      raw = raw.replaceAll(',', '.');
    }
    return double.tryParse(raw);
  }

  Future<void> _startCheckout() async {
    final amount = _parsedAmount;
    if (amount == null || amount < _minAmount) {
      setState(
        () => _error = 'En az 10,00 ₺ tutarında yükleme yapabilirsiniz.',
      );
      return;
    }
    if (amount > _maxAmount) {
      setState(() => _error = 'Tek seferde en fazla 5.000,00 ₺ yüklenebilir.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _starting = true;
      _error = null;
      _waitingHint = null;
    });

    try {
      _session?.dispose();
      _session = null;

      final session = await PaymentGatewayService.instance.startCheckout(
        kind: 'canteen_topup',
        institutionId: widget.instId,
        cardNo: widget.card.cardNo,
        amount: amount,
      );
      if (!mounted) {
        session.dispose();
        return;
      }

      _session = session;
      _paidAmount = amount;
      setState(() {
        _starting = false;
        _step = _TopUpStep.waiting;
      });

      final res = await session.result;
      if (!mounted || _session != session) return;
      _session = null;

      if (res.outcome == PaymentOutcome.cancelled) {
        setState(() {
          _checkingStatus = false;
          _waitingHint = null;
          _step = _TopUpStep.selectAmount;
        });
        return;
      }

      setState(() {
        _checkingStatus = false;
        _resultSuccess = res.isSuccess;
        _resultMessage = res.isSuccess
            ? '${canteenMoney(amount)} tutarındaki bakiye kartınıza yüklendi.'
            : (res.message ?? 'Ödeme tamamlanamadı.');
        _step = _TopUpStep.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = canteenErrorText(e);
      });
    }
  }

  Future<void> _checkStatus() async {
    final session = _session;
    if (session == null || _checkingStatus) return;

    setState(() {
      _checkingStatus = true;
      _waitingHint = null;
    });

    final status = await session.currentStatus();
    if (!mounted || _session != session) return;

    if (status == 'success') {
      _session = null;
      session.dispose();
      setState(() {
        _checkingStatus = false;
        _resultSuccess = true;
        _resultMessage =
            '${canteenMoney(_paidAmount)} tutarındaki bakiye kartınıza yüklendi.';
        _step = _TopUpStep.result;
      });
    } else if (status == 'failed') {
      _session = null;
      session.dispose();
      setState(() {
        _checkingStatus = false;
        _resultSuccess = false;
        _resultMessage = 'Ödeme işlemi tamamlanamadı.';
        _step = _TopUpStep.result;
      });
    } else {
      setState(() {
        _checkingStatus = false;
        _waitingHint =
            'Ödeme henüz onaylanmadı. Açılan sekmede işlemi tamamladığınızda bakiye otomatik yansıyacaktır.';
      });
    }
  }

  void _cancelWaiting() {
    final session = _session;
    _session = null;
    session?.cancel();
    setState(() {
      _checkingStatus = false;
      _waitingHint = null;
      _step = _TopUpStep.selectAmount;
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _waitingHint = null;
      _resultMessage = null;
      _step = _TopUpStep.selectAmount;
    });
  }

  void _closeDialog() {
    if (_starting || _step == _TopUpStep.waiting) return;
    Navigator.of(context).pop(_step == _TopUpStep.result && _resultSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final canClose = !_starting && _step != _TopUpStep.waiting;
    return PopScope(
      canPop: canClose,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Başlık
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kCanteenRedSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: kCanteenRed,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bakiye Yükleme',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'iyzico Güvenli Ödeme',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canClose)
                      IconButton(
                        onPressed: _closeDialog,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF1F5F9),
                          minimumSize: const Size(34, 34),
                          padding: EdgeInsets.zero,
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF475569),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_step == _TopUpStep.selectAmount) _buildSelectStep(),
                if (_step == _TopUpStep.waiting) _buildWaitingStep(),
                if (_step == _TopUpStep.result) _buildResultStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectStep() {
    final currentAmount = _parsedAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Öğrenci Kart Özeti
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kCanteenRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.badge_rounded,
                  size: 18,
                  color: kCanteenRed,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.card.studentName.isEmpty
                          ? 'Kart: ${widget.card.cardNo}'
                          : widget.card.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Kart No: ${widget.card.cardNo}${widget.card.className.isEmpty ? '' : ' • ${widget.card.className}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Mevcut',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    canteenMoney(widget.card.balance),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: kCanteenEmerald,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Hızlı Tutar Seçin',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 10),
        // Figma 4 Renkli Dairesel Tutar Rozetleri (100, 250, 500, 1.000 ₺)
        Row(
          children: [
            for (var i = 0; i < _presets.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _PresetCircleBadge(
                  preset: _presets[i],
                  selected:
                      currentAmount != null &&
                      (currentAmount - _presets[i].amount).abs() < 0.001,
                  enabled: !_starting,
                  onTap: () => setState(() {
                    _amountCtrl.text = '${_presets[i].amount}';
                    _error = null;
                  }),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amountCtrl,
          enabled: !_starting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(8),
          ],
          onChanged: (_) => setState(() => _error = null),
          decoration: canteenInputDecoration(
            label: 'Yüklenecek Tutar (10 ₺ – 5.000 ₺)',
            hint: 'Örn: 250',
            suffixText: '₺',
            prefixIcon: const Icon(
              Icons.payments_outlined,
              color: Color(0xFF64748B),
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 3D Secure / PCI-DSS Bilgi Rozeti
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: kCanteenEmerald,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kart bilgileriniz uygulamada saklanmaz. Ödeme işlemi PCI-DSS uyumlu iyzico 3D Secure güvenli ödeme sayfasında tamamlanır.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Color(0xFF166534),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: canteenFilledStyle(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              radius: 16,
            ),
            onPressed: _starting ? null : _startCheckout,
            icon: _starting
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_rounded, size: 18),
            label: Text(
              _starting
                  ? 'Ödeme Sayfası Açılıyor...'
                  : 'Güvenli Ödeme Sayfasına Git',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingStep() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: kCanteenRedSoft,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                color: kCanteenRed,
                strokeWidth: 3.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            'Tutar: ${canteenMoney(_paidAmount)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Ödeme Bekleniyor',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'iyzico güvenli ödeme sekmesi açıldı. Ödemeyi tamamladığınızda bakiyeniz otomatik yüklenecektir.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_waitingHint != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              _waitingHint!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: canteenFilledStyle(color: kCanteenEmerald),
            onPressed: _checkingStatus ? null : _checkStatus,
            icon: _checkingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Durumu Kontrol Et'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: canteenOutlinedStyle(),
            onPressed: _cancelWaiting,
            child: const Text('Vazgeç'),
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep() {
    final ok = _resultSuccess;
    return Column(
      children: [
        const SizedBox(height: 6),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: ok ? kCanteenEmeraldSoft : kCanteenRedSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: ok ? kCanteenEmerald : kCanteenRed,
            size: 42,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          ok ? 'Bakiye Yüklendi!' : 'Ödeme Tamamlanamadı',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _resultMessage ??
              (ok
                  ? 'Bakiyeniz başarıyla güncellendi.'
                  : 'İşlem sırasında bir sorun oluştu.'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        if (ok)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: canteenFilledStyle(color: kCanteenEmerald),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Kapat'),
            ),
          )
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: canteenFilledStyle(),
              onPressed: _retry,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Tekrar Dene'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: canteenOutlinedStyle(),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Kapat'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PresetCircleBadge extends StatelessWidget {
  final _TopUpPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetCircleBadge({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? preset.color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? preset.color : const Color(0xFFE2E8F0),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: preset.color.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: preset.color.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      preset.display,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                preset.display,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? preset.color : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GÜNLÜK HARCAMA / LİMİT İLERLEME ÇUBUĞU
// ═══════════════════════════════════════════════════════════════════════════

class CanteenLimitBar extends StatelessWidget {
  final double spent;
  final double limit;

  const CanteenLimitBar({super.key, required this.spent, required this.limit});

  @override
  Widget build(BuildContext context) {
    final unlimited = limit <= 0;
    final ratio = unlimited ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final over = !unlimited && spent >= limit;
    final near = !unlimited && !over && ratio >= 0.8;
    final barColor = over
        ? kCanteenRed
        : near
        ? kCanteenAmber
        : kCanteenEmerald;
    final remaining = unlimited
        ? 0.0
        : (limit - spent).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  unlimited
                      ? 'Bugün harcanan: ${canteenMoney(spent)}'
                      : 'Bugün: ${canteenMoney(spent)} / ${canteenMoney(limit)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: unlimited
                      ? kCanteenEmeraldSoft
                      : barColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unlimited
                      ? 'Limitsiz'
                      : over
                      ? 'Limit Doldu'
                      : 'Kalan: ${canteenMoney(remaining)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: unlimited ? kCanteenEmerald : barColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: unlimited ? (spent > 0 ? 0.25 : 0.0) : ratio,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              color: unlimited ? kCanteenEmerald : barColor,
            ),
          ),
        ],
      ),
    );
  }
}
