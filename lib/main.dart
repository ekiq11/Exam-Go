import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/firebas_analytics/firebase_options.dart';
import 'package:examgo/view/home_screen.dart';
import 'package:examgo/view/onboardong_screen.dart';
import 'package:examgo/view/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Portrait only — berlaku untuk semua platform
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pastikan edge-to-edge di Android; iOS akan mengikuti SafeArea
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );

  runApp(const ExamGoApp());
}

class ExamGoApp extends StatelessWidget {
  const ExamGoApp({super.key});

  // OPTIMASI: Cache TextTheme & AppBarStyle sebagai static lazy fields.
  // Diinisialisasi saat build() pertama kali dipanggil (setelah Flutter init),
  // bukan di top-level (yang bisa crash sebelum WidgetsFlutterBinding siap).
  static TextTheme? _cachedTextTheme;
  static TextStyle? _cachedAppBarStyle;

  static TextTheme _textTheme() {
    return _cachedTextTheme ??= GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme);
  }

  static TextStyle _appBarStyle() {
    return _cachedAppBarStyle ??= GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExamGO',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [AnalyticsService.instance.observer],

      // ── Scrollbar tidak muncul di mana-mana (tablet / iOS) ────
      scrollBehavior: const _NoGlowScrollBehavior(),

      theme: ThemeData(
        useMaterial3: false,
        primarySwatch: Colors.green,
        primaryColor: AppColors.primaryGreen,
        scaffoldBackgroundColor: Colors.white,

        // ── Visual density: adaptive agar pas di semua ukuran ───
        visualDensity: VisualDensity.adaptivePlatformDensity,

        textTheme: _textTheme(),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primaryGreen,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: _appBarStyle(),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          primary: AppColors.primaryGreen,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}

/// Hilangkan overscroll glow (Android) dan pastikan scrolling
/// terasa native di semua platform
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child; // hapus glow biru Android

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      // BouncingScrollPhysics di semua platform agar konsisten
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
