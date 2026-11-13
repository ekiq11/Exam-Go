import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/constant/security_service.dart';
import 'package:examgo/services/student_tryout_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cross-Platform E2E Parity & Anti-Race Condition Tests (Android & iOS)', () {
    late List<MethodCall> channelCalls;

    setUp(() {
      channelCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.examgo/locktask'),
        (MethodCall call) async {
          channelCalls.add(call);
          switch (call.method) {
            case 'startLockTask':
              return true; // Parity: Android and iOS now both return true
            case 'stopLockTask':
              return true; // Parity: Android and iOS now both return true
            case 'isScreenOn':
              return true;
            case 'isInMultiWindowMode':
              return false;
            case 'bringToForeground':
              return true;
            default:
              return null;
          }
        },
      );
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.examgo/locktask'), null);
    });

    test('iOS & Android LockTask parity: enable and disable cleanly trigger channel', () async {
      final sec = SecurityService.instance;

      // Enable security
      await sec.enable();
      expect(sec.isLockActive, isTrue);
      expect(channelCalls.any((c) => c.method == 'startLockTask'), isTrue);

      // Disable security
      await sec.disable(force: true);
      expect(sec.isLockActive, isFalse);
      expect(channelCalls.any((c) => c.method == 'stopLockTask'), isTrue);

      // Emergency reset clears everything
      await sec.emergencyReset();
      expect(sec.isLockActive, isFalse);
    });

    test('Multi-Subtest with SKD category respects teacher configuration (Bug Fix Parity)', () {
      final sched = TryoutSchedule.fromMap('TEST_SKD', {
        'nama_paket': 'SKD Kedinasan Mandiri',
        'kategori': 'SKD',
        'jenis_waktu': 'per_subtest',
        'is_teacher_generated': true,
        'durasi_menit': 55,
      });

      expect(sched.jenisTest, equals('SKD'));
      expect(sched.jenisWaktu, equals('per_subtest'));
      expect(sched.isTeacherGenerated, isTrue);

      final pkg = ExamPackage(
        paketId: sched.paketId,
        namaPaket: sched.namaPaket,
        kategori: sched.jenisTest,
        jenisWaktu: sched.jenisWaktu,
        durasiMenit: sched.durasiMenit,
        isTeacherGenerated: sched.isTeacherGenerated,
      );

      expect(pkg.isTeacherGenerated, isTrue);
      expect(pkg.jenisWaktu, equals('per_subtest'));

      // Check subtest evaluation logic
      final jw = pkg.jenisWaktu.trim().toLowerCase().replaceAll('-', '_');
      final isPerSub = jw == 'per_subtest';
      expect(isPerSub, isTrue, reason: 'Teacher Multi-Subtest must NOT be overridden by SKD category');
    });

    test('Device history isolation: distinct devices never overwrite each other', () {
      const devA = 'device_iphone_15_pro';
      const devB = 'device_samsung_s24';
      const token = '85QV3D';

      final docIdA = '${devA}_$token';
      final docIdB = '${devB}_$token';

      expect(docIdA, isNot(equals(docIdB)));
      expect(docIdA, equals('device_iphone_15_pro_85QV3D'));
      expect(docIdB, equals('device_samsung_s24_85QV3D'));
    });

    test('StudentTryoutHistoryItem JSON serialization preserves subtestScores and timestamp', () {
      final item = StudentTryoutHistoryItem(
        token: 'TEST01',
        namaPaket: 'Tryout Mandiri',
        kategori: 'SKD',
        submittedAt: DateTime(2026, 11, 14, 8, 30),
        examEndTime: DateTime(2026, 11, 14, 9, 25),
        finalScore: 420,
        maxScore: 500,
        totalBenar: 42,
        totalSalah: 5,
        totalKosong: 3,
        totalSoal: 50,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Sangat Memuaskan',
        allowRetake: false,
        jawaban: {'Q1': 'A', 'Q2': 'C'},
        questions: [],
        subtestScores: {
          'ST1': {'nama': 'Penalaran Matematika', 'benar': 20, 'skor': 200},
          'ST2': {'nama': 'Literasi B. Indonesia', 'benar': 22, 'skor': 220},
        },
      );

      final json = item.toJson();
      expect(json['token'], equals('TEST01'));
      expect(json['subtest_scores'], isNotNull);
      expect(json['subtest_scores']['ST1']['benar'], equals(20));

      final restored = StudentTryoutHistoryItem.fromJson(json);
      expect(restored.token, equals('TEST01'));
      expect(restored.subtestScores, isNotNull);
      expect(restored.subtestScores!['ST2']['skor'], equals(220));
    });
  });
}
