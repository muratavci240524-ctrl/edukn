import 'dart:async';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart'; // Modern fontlar için
import 'package:intl/date_symbol_data_local.dart'; // For localized dates
import 'package:flutter_web_plugins/url_strategy.dart';
import 'screens/super_admin/admin_login_screen.dart';
import 'screens/super_admin/admin_dashboard_screen.dart';
import 'screens/school/school_login_screen.dart';
import 'screens/school/school_dashboard_v2_screen.dart'; // Yeni sürüm (Deneme)
// import 'screens/school/school_dashboard_screen.dart'; // Eski sürüm (Yedek)
import 'screens/school/profile_settings_screen.dart';
import 'screens/school/school_types/school_types_screen.dart';
import 'screens/school/user_management_screen.dart';
import 'screens/school/school_types/school_type_stats_screen.dart';
import 'screens/school/student_registration_screen.dart';
import 'screens/school/parent_student_selection_screen.dart';
import 'screens/school/terms_screen.dart';
import 'screens/hr/hr_home_screen.dart';
import 'screens/school/school_types/school_type_announcements_screen.dart';
import 'package:edukn/screens/support_services/support_services_hub_screen.dart';
import 'screens/support_services/health/health_screen.dart';
import 'screens/support_services/security/security_gate_screen.dart';
import 'screens/support_services/inventory/inventory_screen.dart';
import 'screens/school/settings/permission_definition_screen.dart';
import 'screens/school/settings/app_settings_screen.dart';
import 'screens/school/settings/sms_integration_screen.dart';
import 'screens/school/kvkk_detail_screen.dart';
import 'screens/public/external_exam_register_screen.dart';
import 'screens/public/external_exam_attendance_screen.dart';
import 'screens/school/registration/pre_registration_screen.dart';
import 'screens/school/accounting/accounting_dashboard_screen.dart';
// --- 1. FIREBASE CORE PAKETLERİNİ IMPORT ET ---
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart'; // FlutterFire CLI'nin oluşturduğu dosya
import 'services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/school/school_types/chat/call/call_service.dart';
import 'screens/school/school_types/chat/call/call_screen_dialog.dart';
import 'services/pwa_update_service.dart';
import 'services/splash/splash_service.dart';
import 'services/user_permission_service.dart';
import 'widgets/edukn_logo.dart';
import 'widgets/read_only_permission_wrapper.dart';
// --- BİTTİ ---

// --- Firebase'i uygulama başlamadan önce başlat ---
void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);

  try {
    debugPrint('🔥 Firebase başlatılıyor...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase başarıyla başlatıldı!');

    if (kIsWeb) {
      try {
        // Web'de IndexedDB persistent target cache (persistenceEnabled: true),
        // Firebase JS SDK 12.12.0'da oturum geçişi ve hot-restart sırasında
        // WatchChangeAggregator (ID: ca9 / b815) çökmesine yol açtığı için
        // bellek içi (in-memory) önbellek kullanılır.
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
        );
        debugPrint(
          '✅ Firestore Web ayarları uygulandı (persistence=false, memoryCache).',
        );
      } catch (e) {
        debugPrint('⚠️ Firestore Settings hatası: $e');
      }
    }

    // 🔒 GHOST LOGIN (HAYALET OTURUM) ÇÖZÜMÜ: Token Kontrolü (Arka Planda, Açılışı Bloke Etmez)
    _verifyAuthTokenInBackground();

    // 🔐 Firebase App Check — Bot ve yetkisiz erişime karşı koruma (Arka Planda Başlatılır)
    if (!kDebugMode) {
      FirebaseAppCheck.instance
          .activate(
            webProvider: ReCaptchaV3Provider(
              '6Levx0gtAAAAALvp-sRrS-PFzvHMtAZ1TMdL6cvq',
            ),
            androidProvider: AndroidProvider.debug,
            appleProvider: AppleProvider.debug,
          )
          .then((_) {
            debugPrint('✅ App Check aktif!');
          })
          .catchError((e) {
            debugPrint('⚠️ App Check aktifleştirilemedi: $e');
          });
    } else {
      debugPrint('ℹ️ Debug modunda App Check devre dışı bırakıldı.');
    }
  } catch (e) {
    debugPrint('❌ Firebase başlatma hatası: $e');
    if (!e.toString().toLowerCase().contains('duplicate')) {
      rethrow; // Duplicate dışındaki hataları fırlat
    }
  }

  runApp(MyApp());
}

/// Token geçerliliğini arka planda sessizce denetler, açılışı geciktirmez.
void _verifyAuthTokenInBackground() async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      debugPrint(
        '🔄 Mevcut kullanıcı bulundu, Auth Token arka planda doğrulanıyor...',
      );
      await currentUser.getIdTokenResult(true);
      debugPrint('✅ Auth Token başarıyla doğrulandı.');
    }
  } catch (e) {
    debugPrint(
      '❌ Auth Token yenileme hatası! Oturum geçersiz. Çıkış yapılıyor: $e',
    );
    try {
      await FirebaseAuth.instance.signOut();
    } catch (silentError) {
      debugPrint('[main] hata yutuldu: $silentError');
    }
  }
}

class MyApp extends StatelessWidget {
  // Uygulamanın ana renk paletini burada tanımlayalım
  static const MaterialColor primaryBrandColor = Colors.blue;
  static const Color lightBackgroundColor = Color(
    0xFFF5F7FA,
  ); // Hafif gri arka plan
  static const Color cardBackgroundColor = Colors.white;

  // Global Navigator Key
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // NotificationService'e navigatorKey'i bağla
    NotificationService.navigatorKey = navigatorKey;

    // PWA Sürüm Güncelleme servisini başlat
    PwaUpdateService.initialize(navigatorKey);

    return _buildApp(context);
  }

  // Orijinal MaterialApp'i oluşturan yardımcı bir metod
  Widget _buildApp(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) {
        return ReadOnlyGlobalGuard(
          child: _GlobalKeyboardUnfocusWrapper(child: child!),
        );
      },
      title: EduKnBrand.appTitle,
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
        // 2. TÜM UYGULAMA İÇİN DİNAMİK KONTRAST GERİ BUTONU TEMASI
        actionIconTheme: ActionIconThemeData(
          backButtonIconBuilder: (BuildContext context) {
            final iconColor = IconTheme.of(context).color ?? Colors.indigo;
            return Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: iconColor,
            );
          },
        ),
        // 3. APPBAR TEMASI (Üst Başlık)
        appBarTheme: AppBarTheme(
          backgroundColor: cardBackgroundColor, // Beyaz appbar
          elevation: 1, // Hafif bir gölge
          iconTheme: const IconThemeData(
            color: Colors.indigo,
            size: 20,
          ), // Beyaz appbar için varsayılan indigo
          actionsIconTheme: const IconThemeData(color: Colors.indigo, size: 20),
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
      onGenerateInitialRoutes: (String initialRouteName) {
        final effectiveName = initialRouteName.trim().isEmpty
            ? '/'
            : initialRouteName;
        final uri = Uri.parse(effectiveName);
        if (uri.path != '/' && uri.path != '/school-login') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SplashService.hide();
          });
        }
        final route =
            _generateAppRoute(RouteSettings(name: effectiveName)) ??
            MaterialPageRoute(
              builder: (_) => SchoolLoginScreen(),
              settings: const RouteSettings(name: '/'),
            );
        return <Route<dynamic>>[route];
      },
      onGenerateRoute: _generateAppRoute,
    );
  }

  Widget _wrapNamedRouteWithPermission(String path, Widget page) {
    final u = UserPermissionService.cachedUserData;
    switch (path) {
      case '/student-registration':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'egitim',
              'ogrenci_kaydi',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'kayit',
              'ogrenci_listesi',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Öğrenci Kaydı',
          child: page,
        );
      case '/pre-registration':
        final canEdit =
            UserPermissionService.canEditSubModule('egitim', 'on_kayit', u) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'kayit',
              'on_kayit',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Aday Öğrenci (Ön Kayıt)',
          child: page,
        );
      case '/accounting':
        return ReadOnlyPermissionWrapper(
          canEdit: UserPermissionService.canEdit('mali_isler', u),
          moduleName: 'Mali İşler',
          child: page,
        );
      case '/terms':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'egitim',
              'donem_islemleri',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'egitim',
              'calisma_takvimi',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Dönem İşlemleri',
          child: page,
        );
      case '/user-management':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'sistem_ayarlari',
              'kullanici_yetkilendirme',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'ayarlar',
              'kullanici_yetki',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Kullanıcı Yetkilendirme',
          child: page,
        );
      case '/hr':
        final canEdit =
            UserPermissionService.canEdit('insan_kaynaklari', u) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'kayit',
              'personel_listesi',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'İnsan Kaynakları',
          child: page,
        );
      case '/announcements':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'haberlesme',
              'genel_duyurular',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'haberlesme',
              'duyurular',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Duyurular',
          child: page,
        );
      case '/support-services':
        final canEdit =
            UserPermissionService.canEdit('hizmetler', u) ||
            UserPermissionService.canEditSchoolTypeModule('destek', u);
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Hizmetler',
          child: page,
        );
      case '/permission-definition':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'sistem_ayarlari',
              'yetki_tanimlama',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'ayarlar',
              'yetki_tanimlama',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Yetki Tanımlama',
          child: page,
        );
      case '/app-settings':
        final canEdit =
            UserPermissionService.canEditSubModule(
              'sistem_ayarlari',
              'uygulama_ayarlari',
              u,
            ) ||
            UserPermissionService.canEditSchoolTypeSubModule(
              'ayarlar',
              'uygulama_ayarlari',
              u,
            );
        return ReadOnlyPermissionWrapper(
          canEdit: canEdit,
          moduleName: 'Uygulama Ayarları',
          child: page,
        );
      case '/sms-settings':
        return ReadOnlyPermissionWrapper(
          canEdit: UserPermissionService.canEditSubModule(
            'sistem_ayarlari',
            'sms_entegrasyonu',
            u,
          ),
          moduleName: 'SMS Entegrasyonu',
          child: page,
        );
      default:
        return page;
    }
  }

  Route<dynamic>? _generateAppRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final path = uri.path.isEmpty ? '/' : uri.path;

    // Extract routes map for query parameter handling
    final Map<String, WidgetBuilder> appRoutes = {
      '/': (context) => SchoolLoginScreen(),
      '/school-login': (context) => SchoolLoginScreen(),
      '/school-dashboard': (context) => SchoolDashboardV2Screen(),
      '/profile-settings': (context) => ProfileSettingsScreen(),
      '/student-registration': (context) => StudentRegistrationScreen(),
      '/pre-registration': (context) => PreRegistrationScreen(),
      '/accounting': (context) => AccountingDashboardScreen(),
      '/terms': (context) => TermsScreen(),
      '/school-types': (context) => SchoolTypesScreen(),
      '/user-management': (context) => UserManagementScreen(),
      '/school-type-stats': (context) => SchoolTypeStatsScreen(),
      '/admin-login': (context) => const AdminLoginScreen(),
      '/admin-dashboard': (context) => const AdminDashboardScreen(),
      '/hr': (context) => const HrHomeScreen(),
      '/announcements': (context) => const SchoolTypeAnnouncementsScreen(),
      '/support-services': (context) => const SupportServicesHubScreen(),
      '/health-portal': (context) =>
          const HealthScreen(isStandalonePortal: true),
      '/security-portal': (context) =>
          const SecurityGateScreen(isStandalonePortal: true),
      '/warehouse-portal': (context) => const InventoryScreen(
        isStandalonePortal: true,
        standaloneMode: 'warehouse',
      ),
      '/purchasing-portal': (context) => const InventoryScreen(
        isStandalonePortal: true,
        standaloneMode: 'purchasing',
      ),
      '/permission-definition': (context) => const PermissionDefinitionScreen(),
      '/app-settings': (context) => const AppSettingsScreen(),
      '/sms-settings': (context) => const SmsIntegrationScreen(),
      '/sinav-basvuru': (context) => const ExternalExamRegisterScreen(),
      '/kvkk-detail': (context) => const KvkkDetailScreen(),
      '/parent-student-selection': (context) => ParentStudentSelectionScreen(
        institutionId: '',
        parentTcNo: '',
        students: [],
      ),
    };

    // Yoklama sayfası: /yoklama-al-{examId}
    if (path.startsWith('/yoklama-al-')) {
      final examId = path.replaceFirst('/yoklama-al-', '');
      return MaterialPageRoute(
        builder: (_) => ExternalExamAttendanceScreen(examId: examId),
        settings: settings,
      );
    }

    if (appRoutes.containsKey(path)) {
      return MaterialPageRoute(
        builder: (context) {
          if (path == '/sinav-basvuru') {
            final examId = uri.queryParameters['examId'];
            return ExternalExamRegisterScreen(examId: examId);
          }
          return _wrapNamedRouteWithPermission(path, appRoutes[path]!(context));
        },
        settings: settings,
      );
    }
    return null;
  }
}

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
  StreamSubscription? _incomingCallSub;
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startGlobalCallListener();
  }

  void _startGlobalCallListener() {
    Future.microtask(() async {
      try {
        if (Firebase.apps.isEmpty) return;
        _authSub = FirebaseAuth.instance.authStateChanges().listen((
          user,
        ) async {
          if (user != null) {
            final capturedUid = user.uid;
            final emailLower = (user.email ?? '').toLowerCase().trim();

            // Firebase Web SDK (12.12.x): giriş anında eş zamanlı Firestore
            // okuma/yazma ve snapshot stream açılması WatchChangeAggregator
            // (ID: ca9 / b815) hatasına yol açabildiği için giriş ekranının
            // ilk okumasını tamamlamasını bekliyoruz.
            await Future.delayed(const Duration(seconds: 3));
            if (!mounted) return;
            if (FirebaseAuth.instance.currentUser?.uid != capturedUid) return;

            // Süper Admin hesabında okul içi arama / FCM kaydı çalıştırılmaz
            if (emailLower == 'superadmin@edukn.com') {
              return;
            }

            // FCM token'ı kaydet ve bildirim servisini başlat
            NotificationService()
                .initialize(uid: capturedUid, forcePermissionPrompt: true)
                .catchError((e) {
                  debugPrint('Notification init error: $e');
                });

            CallService().registerFcmToken();

            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            if (FirebaseAuth.instance.currentUser?.uid != capturedUid) return;

            _incomingCallSub?.cancel();
            _incomingCallSub = CallService().listenForIncomingCalls().listen(
              (incomingCalls) {
                if (incomingCalls.isNotEmpty && mounted) {
                  final activeCall = incomingCalls.first;
                  final navContext = MyApp.navigatorKey.currentContext;
                  if (navContext != null) {
                    CallScreenDialog.showCall(
                      context: navContext,
                      callSession: activeCall,
                      isIncoming: true,
                    );
                  }
                }
              },
              onError: (e) {
                debugPrint('Incoming call stream error: $e');
              },
            );
          } else {
            _incomingCallSub?.cancel();
            NotificationService().reset();
          }
        });
      } catch (e) {
        debugPrint("Global call listener init deferred: $e");
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _incomingCallSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (kIsWeb)
      return; // Web'de window.dart assertion hatasını önlemek için atla

    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      final view =
          dispatcher.implicitView ??
          (dispatcher.views.isNotEmpty ? dispatcher.views.first : null);
      if (view != null && view.viewInsets.bottom == 0.0) {
        // Klavye kapandı: focus'u kaldır
        if (FocusManager.instance.primaryFocus != null &&
            FocusManager.instance.primaryFocus!.hasFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      }
    } catch (silentError) {
      debugPrint('[main] hata yutuldu: $silentError');
    }
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
