import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:examgo/services/app_remote_config.dart';

class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}
class FakeRemoteConfigSettings extends Fake implements RemoteConfigSettings {}

void main() {
  late MockFirebaseRemoteConfig mockRemoteConfig;
  late AppRemoteConfig appRemoteConfig;

  setUpAll(() {
    registerFallbackValue(FakeRemoteConfigSettings());
  });

  setUp(() {
    mockRemoteConfig = MockFirebaseRemoteConfig();
    appRemoteConfig = AppRemoteConfig.createForTest(mockRemoteConfig);
  });

  group('AppRemoteConfig Tests', () {
    test('init() should set defaults and fetch successfully', () async {
      when(() => mockRemoteConfig.setConfigSettings(any()))
          .thenAnswer((_) async {});
      when(() => mockRemoteConfig.setDefaults(any()))
          .thenAnswer((_) async {});
      when(() => mockRemoteConfig.fetchAndActivate())
          .thenAnswer((_) async => true);

      await appRemoteConfig.init();

      verify(() => mockRemoteConfig.setConfigSettings(any())).called(1);
      verify(() => mockRemoteConfig.setDefaults(any())).called(1);
      verify(() => mockRemoteConfig.fetchAndActivate()).called(1);
    });

    test('init() should fail gracefully on network error', () async {
      when(() => mockRemoteConfig.setConfigSettings(any()))
          .thenAnswer((_) async {});
      when(() => mockRemoteConfig.setDefaults(any()))
          .thenAnswer((_) async {});
      when(() => mockRemoteConfig.fetchAndActivate())
          .thenThrow(Exception('Network Error'));

      await appRemoteConfig.init();

      verify(() => mockRemoteConfig.fetchAndActivate()).called(1);
      // It should not throw unhandled exception
    });

    test('getters should return values from FirebaseRemoteConfig', () {
      when(() => mockRemoteConfig.getInt('qr_expiry_minutes')).thenReturn(60);
      when(() => mockRemoteConfig.getInt('exit_press_required')).thenReturn(5);
      when(() => mockRemoteConfig.getInt('max_violations')).thenReturn(4);
      when(() => mockRemoteConfig.getInt('max_scan_history')).thenReturn(15);

      expect(appRemoteConfig.qrExpiryMinutes, 60);
      expect(appRemoteConfig.exitPressRequired, 5);
      expect(appRemoteConfig.maxViolations, 4);
      expect(appRemoteConfig.maxScanHistory, 15);
    });
  });
}
