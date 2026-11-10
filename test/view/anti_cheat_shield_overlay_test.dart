import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/view/widgets/anti_cheat_shield_overlay.dart';

void main() {
  group('AntiCheatShieldOverlay Widget Tests', () {
    testWidgets('Renders child normally when shield is inactive and full screen', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AntiCheatShieldOverlay(
              isShieldActive: false,
              child: Text('SOAL UJIAN RAHASIA #1'),
            ),
          ),
        ),
      );

      expect(find.text('SOAL UJIAN RAHASIA #1'), findsOneWidget);
      expect(find.text('PERINGATAN KEAMANAN UJIAN'), findsNothing);
    });

    testWidgets('Renders opaque shield and warning when isShieldActive is true', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      bool recoverCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AntiCheatShieldOverlay(
              isShieldActive: true,
              onRecover: () => recoverCalled = true,
              child: const Text('SOAL UJIAN RAHASIA #1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERINGATAN KEAMANAN UJIAN'), findsOneWidget);
      expect(find.textContaining('Split-Screen'), findsOneWidget);
      expect(find.text('Kembali ke Layar Penuh'), findsOneWidget);

      await tester.tap(find.text('Kembali ke Layar Penuh'));
      await tester.pump();
      expect(recoverCalled, isTrue);
    });

    testWidgets('Auto-activates shield when screen is in split-screen dimensions (< 500dp height in portrait)', (tester) async {
      // Simulasi layar split-screen: tinggi hanya 400 dp (< 500 dp)
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AntiCheatShieldOverlay(
              isShieldActive: false, // Flag false, tapi dimensi terbelah
              child: Text('SOAL UJIAN RAHASIA #1'),
            ),
          ),
        ),
      );

      // Tirai otomatis muncul menutupi soal karena dimensi layar terbelah
      expect(find.text('PERINGATAN KEAMANAN UJIAN'), findsOneWidget);
    });
  });
}
