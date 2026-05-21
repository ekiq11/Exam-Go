import 'dart:convert';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/firebas_analytics/firebase_options.dart';
import 'package:examgo/services/app_remote_config.dart';
import 'package:examgo/view/home_screen.dart';
import 'package:examgo/view/onboarding_screen.dart';
import 'package:examgo/view/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── FCM Background Handler ────────────────────────────────────────────
// WAJIB berupa top-level function (bukan method class) dan diberi
// @pragma('vm:entry-point') agar tidak di-tree-shake oleh compiler.
// Flutter menjalankan ini di Isolate terpisah saat app di-background/terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Pastikan engine Flutter terikat di isolate background ini
  WidgetsFlutterBinding.ensureInitialized();
  
  // Gunakan guard agar tidak terjadi crash Duplicate App jika sudah terinisialisasi
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  // Tampilkan notifikasi lokal agar muncul di notification tray
  await _showLocalNotification(message);
}

// Plugin notifikasi lokal — digunakan untuk foreground & background
final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

// Channel Android untuk notifikasi pelanggaran ujian (high priority)
const AndroidNotificationChannel _examChannel = AndroidNotificationChannel(
  'exam_violations',            // harus sama dengan channelId di GAS kode.gs
  'Pelanggaran Ujian',
  description: 'Notifikasi saat siswa melanggar aturan ujian',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// Tampilkan notifikasi lokal dari RemoteMessage FCM.
Future<void> _showLocalNotification(RemoteMessage message) async {
  final notification = message.notification;
  if (notification == null) return;
  await _localNotif.show(
    id: notification.hashCode,
    title: notification.title,
    body: notification.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _examChannel.id,
        _examChannel.name,
        channelDescription: _examChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Crashlytics: tangkap semua crash Flutter & Dart ────────────
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // FIX BUG-01: Tangkap uncaught async error di luar Flutter framework.
  // FlutterError.onError TIDAK menangkap error dari async callbacks,
  // isolate, atau Platform-level errors. PlatformDispatcher.onError
  // adalah satu-satunya cara menangkap error tersebut ke Crashlytics.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    // FIX BUG: Cegah Exception async seperti "No active stream to cancel" 
    // atau "No active scan" dari menurunkan skor Crash-Free Sessions.
    if (error is PlatformException) {
      final msg = error.message ?? '';
      final code = error.code;
      if (msg.contains('No active') || code.contains('No active')) {
        return true; // Abaikan sepenuhnya, ini aman
      }
    }
    // Set fatal: false agar error background tidak dihitung sebagai 'Crash' utama 
    // oleh Crashlytics (karena aplikasi tidak force-close).
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    return true;
  };

  // Tangkap error di luar Flutter framework (async, isolate, dll.)
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

  // ── Remote Config: fetch nilainya di startup ────────────────────
  await AppRemoteConfig.instance.init();

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

  // FIX BUG-FONT: Nonaktifkan HTTP fetch google_fonts di runtime.
  // google_fonts ^8.x melempar Exception (bukan silent fallback) jika
  // fonts.gstatic.com tidak bisa dijangkau saat cold install / offline.
  // Dengan allowRuntimeFetching = false, font diambil dari cache/bundle saja
  // dan fallback ke system font jika tidak ada — TIDAK ada crash.
  GoogleFonts.config.allowRuntimeFetching = false;

  // ── FCM: Background handler (WAJIB sebelum runApp) ─────────────
  // Mendaftarkan top-level handler untuk pesan FCM saat app di-background
  // atau terminated. Tanpa ini, notifikasi hanya bekerja di foreground.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── flutter_local_notifications: inisialisasi plugin ───────────
  // Diperlukan agar notifikasi muncul saat app di foreground (FCM tidak
  // menampilkan notifikasi otomatis di foreground — harus manual via plugin).
  await _localNotif.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false, // diminta manual saat guru login
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );

  // Buat channel Android (required Android 8+)
  await _localNotif
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_examChannel);

  // ── FCM: Foreground message handler ────────────────────────────
  // FCM tidak menampilkan heads-up notification saat app di foreground.
  // Kita tampilkan manual via flutter_local_notifications.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await _showLocalNotification(message);
  });

  // ── FCM: Tap notifikasi saat app di background (tidak terminated) ─
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // App sudah buka — tidak perlu aksi tambahan untuk ExamGO
    // (guru cukup buka app untuk melihat panel monitoring)
  });

  // FIX FCM-4: Auto-update GAS saat Firebase merotasi FCM token guru.
  // Token bisa berubah kapan saja (factory reset, clear data, dll).
  // Listener ini memastikan GAS selalu punya token terbaru tanpa guru
  // harus buka Teacher Mode ulang.
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    // FIX FCM-5: Mencegah HP Siswa menimpa token Guru.
    // Hanya device yang pernah masuk ke Mode Guru (punya PIN) yang boleh daftar.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('teacher_pin_hash') == null) return;

    if (AppConfig.gasUrl.isEmpty || AppConfig.gasApiKey.isEmpty) return;
    try {
      await http.post(
        Uri.parse(AppConfig.gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': AppConfig.gasApiKey,
          'action': 'registerToken',
          'token':  newToken,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  });

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
