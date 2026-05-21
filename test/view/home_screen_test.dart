import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:examgo/view/home_screen.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late MockConnectivity mockConnectivity;

  setUpAll(() {
    // Basic setup for platform channels if needed
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    mockConnectivity = MockConnectivity();
    SharedPreferences.setMockInitialValues({});
    
    // Default to online
    when(() => mockConnectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => mockConnectivity.onConnectivityChanged)
        .thenAnswer((_) => Stream.value([ConnectivityResult.wifi]));
  });

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: HomeScreen(),
    );
  }

  group('HomeScreen Widget Tests', () {
    testWidgets('renders main UI components', (WidgetTester tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify app bar texts
      expect(find.text('ExamGO'), findsWidgets);
      
      // Verify connection banner
      expect(find.text('Online'), findsWidgets);
      
      // Verify action cards (assuming they have identifiable texts, we can look for generic terms)
      // Since we don't have the full file content, we just test basic rendering
      expect(find.byType(CustomScrollView), findsOneWidget);
    });

    // We can add more specific tests later, but this serves as the foundational TDD start
    // for UI components.
  });
}
