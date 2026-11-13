import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/view/widgets/examgo_dialog.dart';
import 'package:examgo/view/widgets/popup_ad_dialog.dart';
import 'package:examgo/services/popup_ad_service.dart';
import 'package:examgo/view/student/widgets/tryout_spider_chart_widget.dart';
import 'package:examgo/view/student/widgets/tryout_leaderboard_sheet.dart';
import 'package:examgo/view/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Ukuran layar mobile ekstrem dan standar
  final testViewports = [
    const Size(320, 568), // Ultra kecil (iPhone SE 1st Gen / Entry Android 320dp)
    const Size(360, 740), // Standard Budget Android
    const Size(393, 852), // Modern Flagship (iPhone 15 Pro / Galaxy S24)
    const Size(768, 1024), // Tablet Portait (iPad Mini / Tab S9)
  ];

  group('Mobile Responsive & Anti-Overflow Audit Tests', () {
    testWidgets('ExamGoDialog renders without overflow on 320dp ultra-small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ExamGoDialog.confirm(
                  context,
                  title: 'Konfirmasi Reset Ujian Nasional dengan Judul Panjang',
                  message: 'Apakah Anda yakin ingin membatalkan pengerjaan tryout ini? Seluruh jawaban yang tersimpan di memori lokal akan direset.',
                  confirmText: 'Ya, Reset Sekarang',
                  cancelText: 'Batalkan',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Reset Ujian Nasional dengan Judul Panjang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TryoutSpiderChartWidget renders cleanly on 320dp screen', (tester) async {
      for (final size in testViewports) {
        await tester.binding.setSurfaceSize(size);

        final sampleScores = [
          const TryoutSubScore(name: 'Penalaran Umum (PU)', score: 85, color: Colors.blue),
          const TryoutSubScore(name: 'Pemahaman Bacaan (PBM)', score: 72, color: Colors.purple),
          const TryoutSubScore(name: 'Pengetahuan Kuantitatif (PK)', score: 90, color: Colors.amber),
          const TryoutSubScore(name: 'Literasi Bahasa Inggris', score: 68, color: Colors.teal),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: TryoutSpiderChartWidget(
                  subScores: sampleScores,
                  title: 'Radar Kompetensi Siswa',
                  subtitle: 'Pemetaan penguasaan materi dari seluruh riwayat tryout',
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Radar Kompetensi Siswa'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('PopupAdDialog renders with 1:1 ratio without overflow on 320dp screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));

      const sampleAd = PopupAdItem(
        imageUrl: 'https://images.unsplash.com/photo-1513258496099-48168024aec0',
        ctaUrl: 'https://lynk.id/examgo/siswa-premium',
        title: 'Promo Spesial Paket Tryout UTBK SNBT & CPNS 2026',
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PopupAdDialog.show(context, ad: sampleAd, roleBadge: 'PROMO SISWA'),
                child: const Text('Show Popup Ad'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Popup Ad'));
      await tester.pump(); // Pump frame without pumpAndSettle due to network image mock

      expect(find.text('PROMO SISWA'), findsOneWidget);
      expect(find.text('Promo Spesial Paket Tryout UTBK SNBT & CPNS 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OnboardingScreen renders with zero overflow on all device sizes', (tester) async {
      for (final size in testViewports) {
        await tester.binding.setSurfaceSize(size);

        await tester.pumpWidget(
          MaterialApp(
            routes: {
              '/home': (_) => const Scaffold(body: Text('Home Destination')),
            },
            home: const OnboardingScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SIMULASI CAT BKN & SNBT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('TryoutLeaderboardSheet renders 3-pillar podium and goal comparison on 320dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => TryoutLeaderboardSheet.show(
                  context,
                  token: 'SNBT_TEST_01',
                  title: 'Simulasi UTBK SNBT 2026 Gelombang 1',
                  kategori: 'snbt',
                  userScore: 710,
                ),
                child: const Text('Open Leaderboard'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Leaderboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Peringkat Nasional Peserta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
