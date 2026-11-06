import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/license_service.dart';

void main() {
  group('ActivationResult Tests', () {
    test('ActivationResult.success stores message and targetExamId', () {
      final res = ActivationResult.success('Aktivasi Berhasil!', 'TONAS2026');
      expect(res.isSuccess, isTrue);
      expect(res.message, equals('Aktivasi Berhasil!'));
      expect(res.targetExamId, equals('TONAS2026'));
    });

    test('ActivationResult.failure stores failure message', () {
      final res = ActivationResult.failure('Token tidak valid');
      expect(res.isSuccess, isFalse);
      expect(res.message, equals('Token tidak valid'));
      expect(res.targetExamId, isNull);
    });
  });
}

