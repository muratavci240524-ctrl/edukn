import 'package:flutter/material.dart';
import 'edukn_logo.dart';

/// Standart eduKN AppBar widget'ı.
///
/// PremiumAppBar'ın görsel stilini taşır:
/// - Beyaz arka plan
/// - Alt çizgi: indigo tonunda ince border
/// - Geri butonu: arrow_back_ios_new_rounded, 20px, Colors.indigo
/// - Başlık: indigo.shade900, fontWeight: w900
/// - Subtitle: indigo.shade400, fontSize: 10
///
/// PremiumAppBar'dan farkı: profil, dönem seçici ve arama yok.
/// Bunun yerine her sayfanın kendi [actions] butonları kullanılır.
///
/// Flutter'ın built-in AppBar widget'ını saran bir wrapper'dır,
/// böylece safe area, boyut hesaplaması ve overflow koruması
/// otomatik olarak yönetilir.
///
/// Kullanım:
/// ```dart
/// Scaffold(
///   appBar: EduknAppBar(
///     title: 'Dönem Yönetimi',
///     subtitle: 'Anaokulu',
///     actions: [
///       IconButton(icon: Icon(Icons.sync), onPressed: _sync),
///     ],
///   ),
/// )
/// ```
class EduknAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Ana başlık (sayfa adı)
  final String title;

  /// Opsiyonel alt başlık (okul türü adı vb.)
  final String? subtitle;

  /// Sağ taraftaki action butonları (sayfaya özel)
  final List<Widget>? actions;

  /// Geri butonu gösterilsin mi (varsayılan: true)
  final bool showBackButton;

  /// eduKN logosu gösterilsin mi (varsayılan: true)
  final bool showLogo;

  /// Özel geri butonu davranışı (null ise Navigator.maybePop)
  final VoidCallback? onBack;

  /// TabBar gibi alt widget desteği
  final PreferredSizeWidget? bottom;

  /// leading widget override (showBackButton false ise kullanılabilir)
  final Widget? leading;

  /// centerTitle override
  final bool? centerTitle;

  /// Arka plan rengi (varsayılan: Colors.white)
  final Color? backgroundColor;

  /// Başlık metin rengi (varsayılan: Colors.indigo.shade900)
  final Color? foregroundColor;

  /// Alt başlık metin rengi (varsayılan: Colors.indigo.shade400)
  final Color? subtitleColor;

  /// Geri butonu ikonu rengi (varsayılan: Colors.indigo)
  final Color? backButtonColor;

  /// Alt kenarlık rengi (varsayılan: Colors.indigo.withValues(alpha: 0.05))
  final Color? borderColor;

  const EduknAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showBackButton = true,
    this.showLogo = true,
    this.onBack,
    this.bottom,
    this.leading,
    this.centerTitle,
    this.backgroundColor,
    this.foregroundColor,
    this.subtitleColor,
    this.backButtonColor,
    this.borderColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 1100;

    // ── Leading widget: geri butonu veya özel leading ──
    Widget? leadingWidget;
    if (showBackButton) {
      leadingWidget = IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: backButtonColor ?? Colors.indigo,
        ),
        onPressed: onBack ??
            () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.maybePop(context);
              }
            },
      );
    } else if (leading != null) {
      leadingWidget = leading;
    }

    // ── Title widget: logo + başlık/alt başlık ──
    Widget titleWidget = Row(
      children: [
        if (showLogo) ...[
          const EduKnLogo(iconSize: 24, type: EduKnLogoType.iconOnly),
          const SizedBox(width: 8),
          if (!isMobile) ...[
            Text(
              'eduKN',
              style: TextStyle(
                color: foregroundColor ?? Colors.indigo.shade900,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 20, color: Colors.indigo.withValues(alpha: 0.1)),
            const SizedBox(width: 12),
          ] else ...[
            const SizedBox(width: 4),
          ],
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: centerTitle == true
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: foregroundColor ?? Colors.indigo.shade900,
                  fontSize: isMobile ? 15 : 16,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: subtitleColor ?? Colors.indigo.shade400,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );

    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: backgroundColor ?? Colors.white,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: leadingWidget,
      leadingWidth: showBackButton || leading != null ? 48 : 0,
      titleSpacing: showBackButton || leading != null ? 0 : 16,
      centerTitle: false,
      title: titleWidget,
      actions: [
        if (actions != null) ...actions!,
        const SizedBox(width: 4),
      ],
      bottom: bottom,
      shape: Border(
        bottom: BorderSide(
          color: borderColor ?? Colors.indigo.withValues(alpha: 0.05),
        ),
      ),
    );
  }
}
