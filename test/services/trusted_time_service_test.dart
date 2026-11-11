import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/trusted_time_service.dart';

void main() {
  group('TrustedTimeService Anti-Tamper Tests', () {
    test('isExamTimeEnded returns true when examEndTime is null', () async {
      final service = TrustedTimeService.instance;
      final result = await service.isExamTimeEnded(examEndTime: null);
      expect(result, isTrue);
    });

    test('isExamTimeEnded returns false when examEndTime is in the future', () async {
      final service = TrustedTimeService.instance;
      final futureEndTime = DateTime.now().add(const Duration(hours: 2));
      final result = await service.isExamTimeEnded(
        examEndTime: futureEndTime,
        submittedAt: DateTime.now(),
      );
      expect(result, isFalse);
    });

    test('isExamTimeEnded returns true when examEndTime is in the past', () async {
      final service = TrustedTimeService.instance;
      final pastEndTime = DateTime.now().subtract(const Duration(minutes: 30));
      final result = await service.isExamTimeEnded(
        examEndTime: pastEndTime,
        submittedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(result, isTrue);
    });
  });
}
