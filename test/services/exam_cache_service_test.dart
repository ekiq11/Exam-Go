import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/exam_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ExamCacheService Tests', () {
    test('isExamCached returns false when package is not cached', () async {
      final isCached = await ExamCacheService.instance.isExamCached('SNBT_TEST_01');
      expect(isCached, isFalse);
    });

    test('saveExam saves package, subtests, and questions locally and isExamCached returns true', () async {
      final pkg = ExamPackage(
        paketId: 'SNBT_TEST_01',
        namaPaket: 'Simulasi UTBK SNBT 2025',
        kategori: ExamCategory.snbt,
        jenisWaktu: 'per_subtest',
        durasiMenit: 105,
      );

      final subtests = [
        ExamSubtest(
          subtestId: 'ST_TPS_01',
          paketId: 'SNBT_TEST_01',
          judul: 'Penalaran Umum',
          durasiMenit: 30,
          orderIndex: 1,
        ),
      ];

      final questions = [
        ExamQuestion(
          soalId: 'ST_TPS_01_Q1',
          subtestId: 'ST_TPS_01',
          nomorSoal: 1,
          pertanyaan: 'Jika p maka q. Diketahui p benar. Kesimpulannya?',
          opsiA: 'q benar',
          opsiB: 'q salah',
          opsiC: 'tidak dapat ditentukan',
          opsiD: 'p salah',
          opsiE: 'semua benar',
          kunci: 'A',
          pembahasan: 'Modus Ponens: p -> q, p, maka q.',
        ),
      ];

      await ExamCacheService.instance.saveExam(
        paketId: 'SNBT_TEST_01',
        package: pkg,
        subtests: subtests,
        questions: questions,
      );

      // Verify cached status
      final isCached = await ExamCacheService.instance.isExamCached('SNBT_TEST_01');
      expect(isCached, isTrue);

      // Case-insensitive check
      final isCachedLower = await ExamCacheService.instance.isExamCached('snbt_test_01');
      expect(isCachedLower, isTrue);

      // Verify getCachedPackageIds
      final cachedIds = await ExamCacheService.instance.getCachedPackageIds();
      expect(cachedIds, contains('SNBT_TEST_01'));

      // Verify loadExam
      final loaded = await ExamCacheService.instance.loadExam('SNBT_TEST_01');
      expect(loaded, isNotNull);
      expect(loaded!.package?.namaPaket, equals('Simulasi UTBK SNBT 2025'));
      expect(loaded.subtests.length, equals(1));
      expect(loaded.subtests.first.judul, equals('Penalaran Umum'));
      expect(loaded.questions.length, equals(1));
      expect(loaded.questions.first.soalId, equals('ST_TPS_01_Q1'));
      expect(loaded.questions.first.kunci, equals('A'));
    });

    test('removeExamCache deletes cached package properly', () async {
      final subtests = [
        ExamSubtest(
          subtestId: 'ST_SKD_01',
          paketId: 'SKD_01',
          judul: 'Tes Wawasan Kebangsaan',
          durasiMenit: 30,
        ),
      ];
      final questions = [
        ExamQuestion(
          soalId: 'SKD_01_Q1',
          subtestId: 'ST_SKD_01',
          nomorSoal: 1,
          pertanyaan: 'Pancasila sila ke-1 adalah...',
          kunci: 'A',
        ),
      ];

      await ExamCacheService.instance.saveExam(
        paketId: 'SKD_01',
        subtests: subtests,
        questions: questions,
      );

      expect(await ExamCacheService.instance.isExamCached('SKD_01'), isTrue);

      await ExamCacheService.instance.removeExamCache('SKD_01');

      expect(await ExamCacheService.instance.isExamCached('SKD_01'), isFalse);
      expect(await ExamCacheService.instance.getCachedPackageIds(), isEmpty);
      expect(await ExamCacheService.instance.loadExam('SKD_01'), isNull);
    });
  });
}

