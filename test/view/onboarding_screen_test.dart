import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      routes: {
        '/home': (context) => const Scaffold(body: Text('Home Screen Destination')),
      },
      home: const OnboardingScreen(),
    );
  }

  group('OnboardingScreen Widget Tests', () {
    testWidgets('Renders first slide with badge, title, and feature bullets', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Verifikasi badge dan judul slide 1
      expect(find.text('SIMULASI CAT BKN & SNBT'), findsOneWidget);
      expect(find.text('Raih Skor Tertinggi di'), findsOneWidget);
      expect(find.text('ExamGO'), findsOneWidget);
      expect(find.text('Format Resmi CAT BKN & UTBK-SNBT'), findsOneWidget);

      // Verifikasi tombol navigasi
      expect(find.text('Lewati'), findsOneWidget);
      expect(find.text('Selanjutnya'), findsOneWidget);
    });

    testWidgets('Tapping Selanjutnya advances through slides to Mulai Sekarang', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Slide 1 -> Slide 2
      await tester.tap(find.text('Selanjutnya'));
      await tester.pumpAndSettle();
      expect(find.text('INTEGRITAS ANTI-CURANG'), findsOneWidget);
      expect(find.text('Terkunci Aman'), findsOneWidget);

      // Slide 2 -> Slide 3
      await tester.tap(find.text('Selanjutnya'));
      await tester.pumpAndSettle();
      expect(find.text('ANALITIK SPIDER CHART'), findsOneWidget);
      expect(find.text('Grafik Radar'), findsOneWidget);

      // Slide 3 -> Slide 4 (Slide Terakhir)
      await tester.tap(find.text('Selanjutnya'));
      await tester.pumpAndSettle();
      expect(find.text('CLOUD SYNC & RESTORE'), findsOneWidget);
      expect(find.text('Aman di Cloud'), findsOneWidget);
      expect(find.text('Mulai Sekarang'), findsOneWidget);
      // Di slide terakhir, tombol Lewati disembunyikan
      expect(find.text('Lewati'), findsNothing);

      // Tap Mulai Sekarang -> marks done and goes to Home
      await tester.tap(find.text('Mulai Sekarang'));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Destination'), findsOneWidget);
      final isDone = await isOnboardingDone();
      expect(isDone, isTrue);
    });

    testWidgets('Tapping Lewati marks onboarding done and navigates to home', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lewati'));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Destination'), findsOneWidget);
      final isDone = await isOnboardingDone();
      expect(isDone, isTrue);
    });
  });
}

