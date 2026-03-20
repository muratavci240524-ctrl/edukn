import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart'; // Modern fontlar için
import 'package:intl/date_symbol_data_local.dart'; // For localized dates
import 'screens/super_admin/admin_login_screen.dart';
import 'screens/super_admin/admin_dashboard_screen.dart';
import 'screens/school/school_login_screen.dart';
import 'screens/school/school_dashboard_screen.dart';
import 'screens/school/profile_settings_screen.dart';
import 'screens/school/school_types/school_types_screen.dart';
import 'screens/school/user_management_screen.dart';
import 'screens/school/school_types/school_type_stats_screen.dart';
import 'screens/school/student_registration_screen.dart';
import 'screens/school/terms_screen.dart';
import 'screens/hr/hr_home_screen.dart';
import 'screens/announcements/announcements_screen.dart';
import 'screens/support_services/support_services_hub_screen.dart';
import 'screens/school/settings/permission_definition_screen.dart';
import 'screens/school/settings/app_settings_screen.dart';
import 'screens/school/kvkk_detail_screen.dart';
import 'screens/school/registration/pre_registration_screen.dart';
import 'screens/school/accounting/accounting_dashboard_screen.dart';
// --- 1. FIREBASE CORE PAKETLERİNİ IMPORT ET ---
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // FlutterFire CLI'nin oluşturduğu dosya
// --- BİTTİ ---

// --- Firebase'i uygulama başlamadan önce başlat ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);

  try {
    if (kIsWeb) {
      // Web'de Firebase SDK'ların yüklenmesini bekle
      print('🌐 Web: Firebase SDK yükleniyor...');

      // Debug mode'da SDK'lar daha yavaş yüklenir
      const maxWaitSeconds = 15;
      int attempts = 0;
      bool sdkLoaded = false;

      while (attempts < maxWaitSeconds * 10) {
        try {
          if (js.context.hasProperty('firebase')) {
            print('✅ Firebase SDK hazır (${attempts * 100}ms)');
            sdkLoaded = true;
            break;
          }
        } catch (e) {
          // SDK henüz yüklenmemiş
        }
        await Future.delayed(Duration(milliseconds: 100));
        attempts++;
      }

      if (!sdkLoaded) {
        print('⚠️ Firebase SDK ${maxWaitSeconds} saniyede yüklenemedi!');
        print('ℹ️  Lütfen internet bağlantınızı kontrol edin.');
      } else {
        // SDK yüklendi, initialization için bekle
        print('⏳ Firebase initialization için bekleniyor...');
        await Future.delayed(Duration(seconds: 2));
      }
    }

    print('🔥 Firebase başlatılıyor...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase başarıyla başlatıldı!');
  } catch (e) {
    print('❌ Firebase başlatma hatası: $e');
    if (!e.toString().toLowerCase().contains('duplicate')) {
      rethrow; // Duplicate dışındaki hataları fırlat
    }
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Uygulamanın ana renk paletini burada tanımlayalım
  static const MaterialColor primaryBrandColor = Colors.blue;
  static const Color lightBackgroundColor = Color(
    0xFFF5F7FA,
  ); // Hafif gri arka plan
  static const Color cardBackgroundColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    return _buildApp(context);
  }

  // Orijinal MaterialApp'i oluşturan yardımcı bir metod
  Widget _buildApp(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return _GlobalKeyboardUnfocusWrapper(child: child!);
      },
      title: 'eduKN Yönetim Paneli',
      debugShowCheckedModeBanner: false, // DEBUG etiketini kaldır
      // Türkçe dil desteği
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        // 1. ANA TEMA RENKLERİ
        primarySwatch: primaryBrandColor,
        scaffoldBackgroundColor:
            lightBackgroundColor, // Tüm sayfa arka planları
        fontFamily:
            GoogleFonts.inter().fontFamily, // Modern ve okunaklı bir font
        // 2. APPBAR TEMASI (Üst Başlık)
        appBarTheme: AppBarTheme(
          backgroundColor: cardBackgroundColor, // Beyaz appbar
          elevation: 1, // Hafif bir gölge
          iconTheme: IconThemeData(color: Colors.black87), // Geri butonu vb.
          titleTextStyle: GoogleFonts.inter(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),

        // 3. KART TEMASI (Listeler vb.)
        cardTheme: CardThemeData(
          color: cardBackgroundColor,
          elevation: 0.5, // Çok hafif bir gölge
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0), // Yumuşak kenarlar
            side: BorderSide(
              color: Colors.grey.shade200,
              width: 1,
            ), // İnce bir çerçeve
          ),
        ),

        // 4. GİRİŞ ALANLARI TEMASI (TextField)
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100, // Hafif dolgu rengi
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide.none, // Çerçeve olmasın
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(
              color: primaryBrandColor,
              width: 2,
            ), // Odaklanınca
          ),
          labelStyle: TextStyle(color: Colors.grey.shade700),
        ),

        // 5. BUTON TEMASI (ElevatedButton)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBrandColor, // Ana marka rengi
            foregroundColor: Colors.white, // Buton yazı rengi
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                8.0,
              ), // Yumuşak kenarlı butonlar
            ),
            textStyle: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
      initialRoute: '/school-login', // Varsayılan olarak okul giriş ekranı
      routes: {
        '/school-login': (context) => SchoolLoginScreen(),
        '/school-dashboard': (context) => SchoolDashboardScreen(),
        '/profile-settings': (context) => ProfileSettingsScreen(),
        '/student-registration': (context) => StudentRegistrationScreen(),
        '/pre-registration': (context) => PreRegistrationScreen(),
        '/accounting': (context) => AccountingDashboardScreen(),
        '/terms': (context) => TermsScreen(),
        '/school-types': (context) => SchoolTypesScreen(),
        '/user-management': (context) => UserManagementScreen(),
        '/school-type-stats': (context) => SchoolTypeStatsScreen(),
        '/admin-login': (context) => AdminLoginScreen(),
        '/admin-dashboard': (context) => AdminDashboardScreen(),
        '/hr': (context) => const HrHomeScreen(),
        '/announcements': (context) => const AnnouncementsScreen(),
        '/support-services': (context) => const SupportServicesHubScreen(),
        '/permission-definition': (context) =>
            const PermissionDefinitionScreen(),
        '/app-settings': (context) => const AppSettingsScreen(),
        '/kvkk-detail': (context) => const KvkkDetailScreen(),
      },
    );
  }
}

// --- GLOBAL KEYBOARD UNFOCUS WRAPPER ---
class _GlobalKeyboardUnfocusWrapper extends StatefulWidget {
  final Widget child;
  const _GlobalKeyboardUnfocusWrapper({required this.child});

  @override
  State<_GlobalKeyboardUnfocusWrapper> createState() =>
      __GlobalKeyboardUnfocusWrapperState();
}

class __GlobalKeyboardUnfocusWrapperState
    extends State<_GlobalKeyboardUnfocusWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final view =
          dispatcher.implicitView ??
          (dispatcher.views.isNotEmpty ? dispatcher.views.first : null);
      if (view != null && view.viewInsets.bottom == 0.0) {
        // Klavye kapandığında eğer bir focus varsa sitä unfocus yap
        if (FocusManager.instance.primaryFocus != null &&
            FocusManager.instance.primaryFocus!.hasFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: widget.child,
    );
  }
}
