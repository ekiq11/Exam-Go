import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:examgo/services/app_remote_config.dart';
import 'package:examgo/view/home_screen.dart';

class MockConnectivity extends Mock implements Connectivity {}
class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}
class FakeRemoteConfigSettings extends Fake implements RemoteConfigSettings {}

void main() {
  late MockConnectivity mockConnectivity;
  late MockFirebaseRemoteConfig mockRemoteConfig;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(FakeRemoteConfigSettings());
  });

  setUp(() {
    mockConnectivity = MockConnectivity();
    mockRemoteConfig = MockFirebaseRemoteConfig();

    when(() => mockRemoteConfig.setConfigSettings(any())).thenAnswer((_) async {});
    when(() => mockRemoteConfig.setDefaults(any())).thenAnswer((_) async {});
    when(() => mockRemoteConfig.fetchAndActivate()).thenAnswer((_) async => true);
    when(() => mockRemoteConfig.getInt(any())).thenReturn(0);
    AppRemoteConfig.createForTest(mockRemoteConfig);

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

      expect(find.byType(CustomScrollView), findsOneWidget);
    });
  });
}
