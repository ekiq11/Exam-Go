import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/services/national_exam_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StudentTryoutHistoryService & ExamPackage allowRetake Tests', () {
    test('ExamPackage parses allowRetake correctly', () {
      final pkgSingle = ExamPackage.fromFirestore({
        'paket_id': 'SNBT-002',
        'nama_paket': 'Tryout Nasional 1',
        'allow_retake': false,
      }, 'SNBT-002');
      expect(pkgSingle.allowRetake, isFalse);

      final pkgMulti = ExamPackage.fromFirestore({
        'paket_id': 'SNBT-003',
        'nama_paket': 'Tryout Bebas',
        'allow_retake': true,
      }, 'SNBT-003');
      expect(pkgMulti.allowRetake, isTrue);

      final map = pkgSingle.toFirestore();
      expect(map['allow_retake'], isFalse);
    });

    test('StudentTryoutHistoryService saves and preserves allowRetake flag', () async {
      final service = StudentTryoutHistoryService.instance;

      const eval = ExamEvaluationResult(
        category: ExamCategory.snbt,
        finalScore: 820,
        maxScore: 1000,
        totalBenar: 40,
        totalSalah: 5,
        totalKosong: 5,
        totalSoal: 50,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Sangat Memuaskan',
        subtests: {},
      );

      // Simpan ujian single attempt (allowRetake = false)
      await service.saveAttempt(
        token: 'SNBT-002',
        namaPaket: 'Tryout SNBT 1',
        kategori: 'SNBT',
        result: eval,
        answers: {'1': 'A', '2': 'B'},
        questions: [],
        allowRetake: false,
      );

      final history = await service.getHistory();
      expect(history, hasLength(1));
      expect(history.first.token, 'SNBT-002');
      expect(history.first.allowRetake, isFalse);

      // Simpan ujian multi attempt (allowRetake = true)
      await service.saveAttempt(
        token: 'SNBT-003',
        namaPaket: 'Tryout SNBT 2',
        kategori: 'SNBT',
        result: eval,
        answers: {'1': 'C'},
        questions: [],
        allowRetake: true,
      );

      final history2 = await service.getHistory();
      expect(history2, hasLength(2));
      final item2 = history2.firstWhere((h) => h.token == 'SNBT-003');
      expect(item2.allowRetake, isTrue);
    });
  });
}
