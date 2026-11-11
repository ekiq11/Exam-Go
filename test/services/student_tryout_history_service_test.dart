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

    test('StudentTryoutHistoryItem calculates isExamTimeEnded and remainingExamDuration accurately', () {
      final now = DateTime.now();

      // Case 1: examEndTime is in the future (exam still ongoing)
      final futureEndTime = now.add(const Duration(minutes: 45));
      final itemOngoing = StudentTryoutHistoryItem(
        token: 'TEST-FUT',
        namaPaket: 'Tryout Masih Berjalan',
        kategori: 'CBT',
        submittedAt: now,
        examEndTime: futureEndTime,
        finalScore: 80,
        maxScore: 100,
        totalBenar: 8,
        totalSalah: 2,
        totalKosong: 0,
        totalSoal: 10,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Baik',
        allowRetake: false,
        jawaban: {},
        questions: [],
      );

      expect(itemOngoing.isExamTimeEnded, isFalse);
      expect(itemOngoing.remainingExamDuration, isNotNull);
      expect(itemOngoing.remainingExamDuration!.inMinutes, inInclusiveRange(44, 45));

      // Case 2: examEndTime is in the past (exam ended)
      final pastEndTime = now.subtract(const Duration(minutes: 10));
      final itemEnded = itemOngoing.copyWith(examEndTime: pastEndTime);

      expect(itemEnded.isExamTimeEnded, isTrue);
      expect(itemEnded.remainingExamDuration, Duration.zero);

      // Case 3: examEndTime is null (defaults to ended / open)
      final itemNull = StudentTryoutHistoryItem(
        token: 'TEST-NULL',
        namaPaket: 'Tryout Bebas',
        kategori: 'CBT',
        submittedAt: now,
        examEndTime: null,
        finalScore: 80,
        maxScore: 100,
        totalBenar: 8,
        totalSalah: 2,
        totalKosong: 0,
        totalSoal: 10,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Baik',
        allowRetake: false,
        jawaban: {},
        questions: [],
      );
      expect(itemNull.isExamTimeEnded, isTrue);
      expect(itemNull.remainingExamDuration, isNull);

      // Serialization & Deserialization
      final json = itemOngoing.toJson();
      expect(json['exam_end_time'], isNotNull);
      final deserialized = StudentTryoutHistoryItem.fromJson(json);
      expect(deserialized.examEndTime, isNotNull);
      expect(deserialized.isExamTimeEnded, isFalse);
    });

    test('StudentTryoutHistoryService.maskName obscures student name appropriately', () {
      expect(StudentTryoutHistoryService.maskName('Ahmad Subki'), 'Ahmad S.');
      expect(StudentTryoutHistoryService.maskName('Budi'), 'Bud***');
      expect(StudentTryoutHistoryService.maskName('Joe'), 'Joe');
      expect(StudentTryoutHistoryService.maskName('Alexander'), 'Ale***');
      expect(StudentTryoutHistoryService.maskName(''), 'Siswa ExamGO');
    });

    test('getNationalLeaderboard returns 100% real data without dummy cohort injection', () async {
      final service = StudentTryoutHistoryService.instance;

      final result = await service.getNationalLeaderboard(
        token: 'SNBT-REAL-001',
        kategori: 'SNBT',
        userScore: 785,
        userName: 'Ahmad Subki',
      );

      // Verify that no synthetic cohort (e.g. 20 fake students) is created
      expect(result.entries.length, lessThanOrEqualTo(1));
      if (result.entries.isNotEmpty) {
        expect(result.entries.first.isCurrentUser, isTrue);
        expect(result.entries.first.score, 785);
        expect(result.entries.first.name, 'Ahmad S.');
        expect(result.userRank, 1);
        expect(result.totalParticipants, 1);
      }

      // Ensure none of the old dummy cohort names exist
      final dummyNames = ['Rizky A.', 'Nabila S.', 'Fathir M.', 'Putri W.'];
      for (final dummy in dummyNames) {
        expect(result.entries.any((e) => e.name == dummy), isFalse);
      }
    });
  });
}
