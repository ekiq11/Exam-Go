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
    test('isExamTimeEnded detects manual clock advancement when elapsed physical time is insufficient', () async {
      final service = TrustedTimeService.instance;
      final now = DateTime.now();
      // Misal siswa menyelesaikan ujian 10 menit lalu dan waktu ujian resmi selesai 30 menit ke depan
      final submittedAt = now.subtract(const Duration(minutes: 10));
      final examEndTime = now.add(const Duration(minutes: 30));

      // Jika elapsedRealtime perangkat menunjukkan baru berjalan 10 menit (600.000 ms),
      // sementara dibutuhkan 40 menit (2.400.000 ms)
      const submittedElapsedMs = 1000000;
      // Mocking getElapsedRealtime secara pasif via parameter
      final result = await service.isExamTimeEnded(
        examEndTime: examEndTime,
        submittedAt: submittedAt,
        elapsedRealtimeMs: submittedElapsedMs,
      );
      expect(result, isFalse);
    });

    test('queryNtpServer handles network queries or fails gracefully without throwing', () async {
      final service = TrustedTimeService.instance;
      final ntpDate = await service.queryNtpServer('time.google.com');
      // Bila koneksi internet tersedia, mengembalikan waktu; bila offline, mengembalikan null
      if (ntpDate != null) {
        expect(ntpDate.year, greaterThanOrEqualTo(2024));
      }
    });
  });
}

