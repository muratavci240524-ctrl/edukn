import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/web_notification/web_notification.dart'
    if (dart.library.html) '../services/web_notification/web_notification_web.dart';

class NotificationPromptDialog extends StatefulWidget {
  final String? uid;

  const NotificationPromptDialog({Key? key, this.uid}) : super(key: key);

  /// Bildirim izni kapalıysa diyaloğu gösterir
  static Future<bool?> checkAndShow(BuildContext context, {String? uid}) async {
    final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (effectiveUid == null) return null;

    if (kIsWeb) {
      final status = getWebNotificationPermissionStatus();
      // Zaten izin verilmişse tekrar sorma
      if (status == 'granted') {
        return false;
      }
    }

    if (!context.mounted) return null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => NotificationPromptDialog(uid: effectiveUid),
    );
  }

  @override
  State<NotificationPromptDialog> createState() => _NotificationPromptDialogState();
}

class _NotificationPromptDialogState extends State<NotificationPromptDialog> {
  bool _isRequesting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final isIos = kIsWeb && isIosWeb();
    final isStandalone = kIsWeb && isStandalonePwa();
    final needsIosHomeScreen = isIos && !isStandalone;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // İkon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: needsIosHomeScreen
                      ? [Colors.blue.shade600, Colors.indigo.shade700]
                      : [const Color(0xFF4C59BC), const Color(0xFF6B7AE8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4C59BC).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                needsIosHomeScreen ? Icons.add_to_home_screen_rounded : Icons.notifications_active_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Başlık
            Text(
              needsIosHomeScreen ? 'Bildirimleri Aktif Edin' : 'Bildirimleri Açın',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E2661),
              ),
            ),
            const SizedBox(height: 10),

            // Açıklama
            Text(
              needsIosHomeScreen
                  ? 'iPhone (Safari) üzerinden nöbet ve duyuru bildirimlerini alabilmek için uygulamayı ana ekranınıza eklemeniz gerekmektedir.'
                  : 'Nöbet görevlerinizi, acil okul duyurularını ve mesajları anında telefonunuzda görebilmek için bildirimlere izin verin.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // iOS Safari İçin Adım Adım Rehber
            if (needsIosHomeScreen) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  children: [
                    _buildStepRow(
                      step: '1',
                      icon: Icons.ios_share_rounded,
                      text: 'Safari\'nin alt çubuğundaki Paylaş butonuna dokunun.',
                    ),
                    const SizedBox(height: 12),
                    _buildStepRow(
                      step: '2',
                      icon: Icons.add_box_outlined,
                      text: 'Menüden "Ana Ekrana Ekle" seçeneğini seçin.',
                    ),
                    const SizedBox(height: 12),
                    _buildStepRow(
                      step: '3',
                      icon: Icons.check_circle_outline_rounded,
                      text: 'Ana ekrana gelen eduKN uygulamasını açarak bildirimleri hemen alın.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Hata / Bilgi mesajı
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Butonlar
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!needsIosHomeScreen) ...[
                  ElevatedButton(
                    onPressed: _isRequesting ? null : _handleRequestPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4C59BC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: _isRequesting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.notifications_active_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Bildirimleri Aç',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                ],

                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    needsIosHomeScreen ? 'Anladım, Kapat' : 'Şimdilik Geç',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow({required String step, required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF4C59BC),
          child: Text(
            step,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: const Color(0xFF4C59BC)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF1E2661),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRequestPermission() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });

    try {
      String? result;
      if (kIsWeb) {
        result = await requestWebNotificationPermission();
      } else {
        final settings = await NotificationService().requestPermission(force: true);
        result = settings?.authorizationStatus.name;
      }

      if (result == 'granted') {
        final uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          // FCM token'ı hemen üretip kaydet
          await NotificationService().initialize(uid: uid, forcePermissionPrompt: false);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'Bildirimler başarıyla aktif edildi!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else if (result == 'denied') {
        if (mounted) {
          setState(() {
            _errorMessage = 'Bildirim izni tarayıcınızda engellendi. Adres çubuğundaki kilit/ayar simgesinden izin verip sayfayı yenileyebilirsiniz.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Bildirim izni onaylanmadı. Dilediğiniz zaman tekrar açabilirsiniz.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'İzin istenirken bir sorun oluştu: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }
}
