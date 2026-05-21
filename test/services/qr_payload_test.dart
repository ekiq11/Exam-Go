import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:examgo/services/app_remote_config.dart';
import 'package:examgo/services/qr_payload.dart';
import 'package:examgo/constant/app_config.dart';

class MockFirebaseRemoteConfig extends Mock implements FirebaseRemoteConfig {}

void main() {
  late MockFirebaseRemoteConfig mockRemoteConfig;

  setUp(() {
    mockRemoteConfig = MockFirebaseRemoteConfig();
    AppRemoteConfig.instance = AppRemoteConfig.createForTest(mockRemoteConfig);
    when(() => mockRemoteConfig.getInt('qr_expiry_minutes')).thenReturn(10080); // 7 days
  });

  group('QRPayloadService Tests', () {
    test('generate() creates a valid signed payload', () {
      final payload = QRPayloadService.generate('https://exam.com', title: 'Math');
      
      expect(payload, isNotEmpty);
      expect(QRPayloadService.looksLikeExamQR(payload), isTrue);
      
      final parsed = QRPayloadService.validate(payload);
      expect(parsed, isNotNull);
      expect(parsed!.url, 'https://exam.com');
      expect(parsed.title, 'Math');
      expect(parsed.version, AppConfig.qrFormatVersion);
      expect(parsed.nonce, isNotEmpty);
    });

    test('validate() returns null for invalid signature', () {
      final payload = QRPayloadService.generate('https://exam.com', title: 'Math');
      
      // Tamper with the signature
      final Map<String, dynamic> decoded = jsonDecode(payload);
      decoded['sig'] = 'invalid_signature_123';
      final tamperedPayload = jsonEncode(decoded);
      
      final parsed = QRPayloadService.validate(tamperedPayload);
      expect(parsed, isNull);
    });

    test('validate() returns null for expired payload', () {
      // Generate a payload and set its timestamp to 8 days ago
      final timestamp = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch ~/ 1000;
      final data = jsonEncode({
        'v': AppConfig.qrFormatVersion,
        'url': 'https://exam.com',
        'title': 'Math',
        'ts': timestamp,
        'nonce': '123456',
      });
      
      // Sign the payload manually with the new timestamp
      final hmac = Hmac(sha256, utf8.encode(AppConfig.qrSecretKey));
      final sig = hmac.convert(utf8.encode(data)).toString();
      final payload = jsonEncode({'app': AppConfig.qrPrefix, 'data': data, 'sig': sig});
      
      final parsed = QRPayloadService.validate(payload);
      expect(parsed, isNull);
    });
  });
}
