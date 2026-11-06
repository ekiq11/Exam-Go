import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/national_exam_evaluator.dart';

void main() {
  group('NationalExamEvaluator Tests', () {
    test('SKD: Menghitung skor TWK (+5), TIU (+5), dan TKP bertingkat (1-5)', () {
      final twkQuestions = List.generate(
        10,
        (i) => ExamQuestion(
          soalId: 'TWK_$i',
          subtestId: 'ST_TWK',
          nomorSoal: i + 1,
          pertanyaan: 'Soal TWK $i',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'A',
        ),
      );

      final tiuQuestions = List.generate(
        10,
        (i) => ExamQuestion(
          soalId: 'TIU_$i',
          subtestId: 'ST_TIU',
          nomorSoal: i + 1,
          pertanyaan: 'Soal TIU $i',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'B',
        ),
      );

      final tkpQuestions = List.generate(
        10,
        (i) => ExamQuestion(
          soalId: 'TKP_$i',
          subtestId: 'ST_TKP',
          nomorSoal: i + 1,
          pertanyaan: 'Soal TKP $i',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'D,B,A,C,E', // D=5, B=4, A=3, C=2, E=1
        ),
      );

      final subtests = [
        ExamSubtest(subtestId: 'ST_TWK', paketId: 'P1', judul: 'Tes Wawasan Kebangsaan (TWK)', soalList: twkQuestions),
        ExamSubtest(subtestId: 'ST_TIU', paketId: 'P1', judul: 'Tes Inteligensia Umum (TIU)', soalList: tiuQuestions),
        ExamSubtest(subtestId: 'ST_TKP', paketId: 'P1', judul: 'Tes Karakteristik Pribadi (TKP)', soalList: tkpQuestions),
      ];

      final allQuestions = [...twkQuestions, ...tiuQuestions, ...tkpQuestions];

      final answers = <String, String>{};
      // TWK: Jawab 10 soal benar (10 x 5 = 50)
      for (final q in twkQuestions) {
        answers[q.soalId] = 'A';
      }
      // TIU: Jawab 10 soal benar (10 x 5 = 50)
      for (final q in tiuQuestions) {
        answers[q.soalId] = 'B';
      }
      // TKP: Jawab D pada 5 soal (5 x 5 = 25), B pada 5 soal (5 x 4 = 20) -> total 45
      for (int i = 0; i < 5; i++) {
        answers[tkpQuestions[i].soalId] = 'D';
      }
      for (int i = 5; i < 10; i++) {
        answers[tkpQuestions[i].soalId] = 'B';
      }

      final result = NationalExamEvaluator.evaluate(
        category: 'SKD',
        subtests: subtests,
        allQuestions: allQuestions,
        answers: answers,
      );

      expect(result.subtests['ST_TWK']!.skor, 50);
      expect(result.subtests['ST_TIU']!.skor, 50);
      expect(result.subtests['ST_TKP']!.skor, 45);
      expect(result.finalScore, 145);
      expect(result.totalBenar, 30);
      expect(result.totalSalah, 0);
      expect(result.totalKosong, 0);
    });

    test('SNBT: Mengonversi skor subtes ke skala UTBK 0 - 1000 dan menghitung rata-rata', () {
      final questions1 = List.generate(
        10,
        (i) => ExamQuestion(
          soalId: 'Q1_$i',
          subtestId: 'ST1',
          nomorSoal: i + 1,
          pertanyaan: 'Soal UTBK 1',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'A',
        ),
      );

      final questions2 = List.generate(
        10,
        (i) => ExamQuestion(
          soalId: 'Q2_$i',
          subtestId: 'ST2',
          nomorSoal: i + 1,
          pertanyaan: 'Soal UTBK 2',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'B',
        ),
      );

      final subtests = [
        ExamSubtest(subtestId: 'ST1', paketId: 'P_SNBT', judul: 'Penalaran Umum', soalList: questions1),
        ExamSubtest(subtestId: 'ST2', paketId: 'P_SNBT', judul: 'Pengetahuan Kuantitatif', soalList: questions2),
      ];

      final allQuestions = [...questions1, ...questions2];

      final answers = <String, String>{};
      // ST1: 8 benar dari 10 soal -> (8/10)*1000 = 800
      for (int i = 0; i < 8; i++) {
        answers[questions1[i].soalId] = 'A';
      }
      // ST2: 6 benar dari 10 soal -> (6/10)*1000 = 600
      for (int i = 0; i < 6; i++) {
        answers[questions2[i].soalId] = 'B';
      }

      final result = NationalExamEvaluator.evaluate(
        category: 'SNBT',
        subtests: subtests,
        allQuestions: allQuestions,
        answers: answers,
        customPassingPercentage: 65, // target 650
      );

      expect(result.subtests['ST1']!.skor, 800);
      expect(result.subtests['ST1']!.predikat, 'Sangat Memuaskan');
      expect(result.subtests['ST2']!.skor, 600);
      expect(result.subtests['ST2']!.predikat, 'Cukup');

      // Rata-rata: (800 + 600) / 2 = 700
      expect(result.finalScore, 700);
      expect(result.isPassed, true);
      expect(result.statusKelulusan, 'LULUS TARGET AMBANG BATAS UTBK');
    });

    test('TKA: Mengonversi skor ke skala akademik 0 - 100 dan mengevaluasi KKM', () {
      final questions = List.generate(
        20,
        (i) => ExamQuestion(
          soalId: 'Q_$i',
          subtestId: 'ST_TKA',
          nomorSoal: i + 1,
          pertanyaan: 'Soal Matematika IPA',
          opsiA: 'A',
          opsiB: 'B',
          opsiC: 'C',
          opsiD: 'D',
          opsiE: 'E',
          kunci: 'C',
        ),
      );

      final subtests = [
        ExamSubtest(subtestId: 'ST_TKA', paketId: 'P_TKA', judul: 'Matematika IPA', soalList: questions),
      ];

      final answers = <String, String>{};
      // Jawab 16 benar dari 20 soal -> 80
      for (int i = 0; i < 16; i++) {
        answers[questions[i].soalId] = 'C';
      }

      final result = NationalExamEvaluator.evaluate(
        category: 'TKA SMA',
        subtests: subtests,
        allQuestions: questions,
        answers: answers,
        customPassingPercentage: 75,
      );

      expect(result.subtests['ST_TKA']!.skor, 80);
      expect(result.subtests['ST_TKA']!.predikat, 'Baik');
      expect(result.finalScore, 80);
      expect(result.isPassed, true);
      expect(result.statusKelulusan, 'LULUS (MEMENUHI KKM)');
    });
  });
}
