import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/view/widgets/app_back_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackButton Tests', () {
    testWidgets('Renders AppBackButton.light correctly on dark/gradient appbars', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF2E7D32),
              leading: AppBackButton.light(
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppBackButton), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Renders AppBackButton.dark correctly on light appbars', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              leading: AppBackButton.dark(
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppBackButton), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Renders AppBackButton.close correctly for modals/scanners', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              leading: AppBackButton.close(
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppBackButton), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('Pops navigator by default if onPressed is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => Scaffold(
                        appBar: AppBar(
                          leading: const AppBackButton.light(),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open Page'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Page'));
      await tester.pumpAndSettle();

      expect(find.byType(AppBackButton), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      expect(find.byType(AppBackButton), findsNothing);
      expect(find.text('Open Page'), findsOneWidget);
    });
  });
}
