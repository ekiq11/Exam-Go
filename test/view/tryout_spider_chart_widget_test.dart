import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/view/student/widgets/tryout_card_widget.dart';
import 'package:examgo/view/student/widgets/tryout_spider_chart_widget.dart';

void main() {
  group('TryoutSubScore Logic Tests', () {
    test('fromHistoryItem computes scores from grouped questions correctly', () {
      final questions = [
        ExamQuestion(
          soalId: 'q1',
          subtestId: 'Penalaran Umum',
          nomorSoal: 1,
          pertanyaan: 'Soal 1',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'A',
          pembahasan: '',
        ),
        ExamQuestion(
          soalId: 'q2',
          subtestId: 'Penalaran Umum',
          nomorSoal: 2,
          pertanyaan: 'Soal 2',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'B',
          pembahasan: '',
        ),
        ExamQuestion(
          soalId: 'q3',
          subtestId: 'Pengetahuan Kuantitatif',
          nomorSoal: 3,
          pertanyaan: 'Soal 3',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'C',
          pembahasan: '',
        ),
        ExamQuestion(
          soalId: 'q4',
          subtestId: 'Literasi Bahasa',
          nomorSoal: 4,
          pertanyaan: 'Soal 4',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'D',
          pembahasan: '',
        ),
      ];

      final item = StudentTryoutHistoryItem(
        token: 'SNBT-01',
        namaPaket: 'Tryout SNBT 2026',
        kategori: 'SNBT',
        submittedAt: DateTime.now(),
        finalScore: 750,
        maxScore: 1000,
        totalBenar: 3,
        totalSalah: 1,
        totalKosong: 0,
        totalSoal: 4,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'Sangat Memuaskan',
        allowRetake: true,
        jawaban: {'q1': 'A', 'q2': 'C', 'q3': 'C', 'q4': 'D'},
        questions: questions,
      );

      final scores = TryoutSubScore.fromHistoryItem(item);
      expect(scores.length, 3);
      
      // q1 benar, q2 salah => 50%
      final pu = scores.firstWhere((s) => s.name.contains('Penalaran') || s.name == 'PU');
      expect(pu.score, 50.0);
      expect(pu.totalBenar, 1);
      expect(pu.totalSoal, 2);

      // q3 benar => 100%
      final pk = scores.firstWhere((s) => s.name.contains('Kuantitatif') || s.name == 'PK');
      expect(pk.score, 100.0);

      // q4 benar => 100%
      final lb = scores.firstWhere((s) => s.name.contains('Literasi') || s.name == 'LB');
      expect(lb.score, 100.0);
    });

    test('fromHistoryItem handles empty questions gracefully with adaptive fallback', () {
      final item = StudentTryoutHistoryItem(
        token: 'SKD-01',
        namaPaket: 'Tryout SKD CPNS',
        kategori: 'SKD',
        submittedAt: DateTime.now(),
        finalScore: 400,
        maxScore: 500,
        totalBenar: 80,
        totalSalah: 20,
        totalKosong: 0,
        totalSoal: 100,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'A',
        allowRetake: true,
        jawaban: {},
        questions: [],
      );

      final scores = TryoutSubScore.fromHistoryItem(item);
      expect(scores.length, greaterThanOrEqualTo(3));
      expect(scores.any((s) => s.name == 'Ketepatan'), isTrue);
    });

    test('fromCumulativeHistory combines multiple history items', () {
      final item1 = StudentTryoutHistoryItem(
        token: 'T1',
        namaPaket: 'Tryout 1',
        kategori: 'SNBT',
        submittedAt: DateTime.now(),
        finalScore: 80,
        maxScore: 100,
        totalBenar: 8,
        totalSalah: 2,
        totalKosong: 0,
        totalSoal: 10,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'A',
        allowRetake: true,
        jawaban: {},
        questions: [],
      );

      final item2 = StudentTryoutHistoryItem(
        token: 'T2',
        namaPaket: 'Tryout 2',
        kategori: 'SKD',
        submittedAt: DateTime.now(),
        finalScore: 60,
        maxScore: 100,
        totalBenar: 6,
        totalSalah: 4,
        totalKosong: 0,
        totalSoal: 10,
        isPassed: false,
        statusKelulusan: 'TIDAK LULUS',
        predikat: 'C',
        allowRetake: true,
        jawaban: {},
        questions: [],
      );

      final cumulative = TryoutSubScore.fromCumulativeHistory([item1, item2]);
      expect(cumulative.length, greaterThanOrEqualTo(3));
    });

    test('fromQuestions calculates subscores accurately', () {
      final questions = [
        ExamQuestion(
          soalId: 'q1',
          subtestId: 'Subtest 1',
          nomorSoal: 1,
          pertanyaan: 'Q1',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'A',
          pembahasan: '',
        ),
        ExamQuestion(
          soalId: 'q2',
          subtestId: 'Subtest 2',
          nomorSoal: 2,
          pertanyaan: 'Q2',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'B',
          pembahasan: '',
        ),
        ExamQuestion(
          soalId: 'q3',
          subtestId: 'Subtest 3',
          nomorSoal: 3,
          pertanyaan: 'Q3',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'C',
          pembahasan: '',
        ),
      ];

      final scores = TryoutSubScore.fromQuestions(
        questions: questions,
        studentAnswers: {'q1': 'A', 'q2': 'C', 'q3': 'C'},
        kategori: 'UMUM',
      );

      expect(scores.length, 3);
      expect(scores[0].score, 100.0); // q1 benar
      expect(scores[1].score, 0.0);   // q2 salah
      expect(scores[2].score, 100.0); // q3 benar
    });
  });

  group('TryoutSpiderChartWidget Tests', () {
    testWidgets('renders title and radar canvas properly', (tester) async {
      final scores = [
        const TryoutSubScore(name: 'TWK', score: 85, color: Colors.blue),
        const TryoutSubScore(name: 'TIU', score: 90, color: Colors.green),
        const TryoutSubScore(name: 'TKP', score: 78, color: Colors.amber),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TryoutSpiderChartWidget(
              subScores: scores,
              title: 'Radar Kemampuan SKD',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Radar Kemampuan SKD'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('TWK'), findsWidgets);
      expect(find.text('TIU'), findsWidgets);
      expect(find.text('TKP'), findsWidgets);
    });
  });

  group('TryoutCardWidget Badges Tests', () {
    final schedule = TryoutSchedule(
      paketId: 'SNBT-01',
      namaPaket: 'Simulasi UTBK SNBT 2026',
      jenisTest: 'SNBT',
      tanggal: '2026-12-01',
      jamMulai: '08:00',
      jamSelesai: '11:00',
      durasiMenit: 180,
      totalSoal: 155,
      subtests: [],
      allowRetake: true,
    );

    testWidgets('renders BARU badge when isNew is true and not attempted', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TryoutCardWidget(
              schedule: schedule,
              isNew: true,
              isAttempted: false,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('BARU'), findsOneWidget);
      expect(find.textContaining('Sudah Dikerjakan'), findsNothing);
    });

    testWidgets('renders Sudah Dikerjakan badge when isAttempted is true', (tester) async {
      final history = StudentTryoutHistoryItem(
        token: 'SNBT-01',
        namaPaket: 'Simulasi UTBK SNBT 2026',
        kategori: 'SNBT',
        submittedAt: DateTime.now(),
        finalScore: 820,
        maxScore: 1000,
        totalBenar: 120,
        totalSalah: 30,
        totalKosong: 5,
        totalSoal: 155,
        isPassed: true,
        statusKelulusan: 'LULUS',
        predikat: 'A',
        allowRetake: true,
        jawaban: {},
        questions: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TryoutCardWidget(
              schedule: schedule,
              isNew: true, // Should be superseded by isAttempted
              isAttempted: true,
              historyItem: history,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sudah Dikerjakan (Skor: 820)'), findsOneWidget);
      expect(find.text('BARU'), findsNothing);
    });
  });
}
