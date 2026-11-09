import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/services/student_tryout_history_service.dart';

void main() {
  group('Version 8.0.0 Verification', () {
    test('AppConfig has version 8.0.0 and synchronized build number', () {
      expect(AppConfig.appVersion, equals('8.0.0'));
      expect(AppConfig.appBuildNumber, equals(44));
    });
  });

  group('StudentTryoutHistoryItem & Metrics Calculation', () {
    test('Calculates accuracy and passing metrics proportionally', () {
      final item = StudentTryoutHistoryItem(
        token: 'SNBT-001',
        namaPaket: 'Try Out Akbar UTBK SNBT 2026',
        kategori: 'SNBT (UTBK)',
        submittedAt: DateTime(2026, 11, 9, 14, 30),
        finalScore: 850,
        maxScore: 1000,
        totalBenar: 85,
        totalSalah: 10,
        totalKosong: 5,
        totalSoal: 100,
        isPassed: true,
        statusKelulusan: 'LULUS PASSING GRADE',
        predikat: 'Sangat Memuaskan',
        allowRetake: true,
        jawaban: const {'1': 'A', '2': 'B'},
        questions: const [],
      );

      final totalSoal = item.totalSoal > 0
          ? item.totalSoal
          : (item.totalBenar + item.totalSalah + item.totalKosong);
      final accuracy = ((item.totalBenar / totalSoal) * 100).round();

      expect(item.finalScore, equals(850));
      expect(item.maxScore, equals(1000));
      expect(totalSoal, equals(100));
      expect(accuracy, equals(85));
      expect(item.isPassed, isTrue);
      expect(item.allowRetake, isTrue);
    });
  });
}
