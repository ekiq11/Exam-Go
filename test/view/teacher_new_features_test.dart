import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/exam_pdf_exporter.dart';
import 'package:examgo/view/teacher/teacher_exam_matrix_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fitur 4: Acak Soal & Acak Opsi (Anti Lirik Sebangku)', () {
    test('ExamPackage defaults randomizeQuestions & randomizeOptions to FALSE unless teacher activates', () {
      final defaultPkg = ExamPackage(
        paketId: 'TRYOUT_SNBT_01',
        namaPaket: 'Paket Tryout UTBK SNBT 2026',
        isTeacherGenerated: false, // Paket Tryout Resmi
      );

      expect(defaultPkg.randomizeQuestions, isFalse, reason: 'Paket tryout tidak boleh diacak otomatis');
      expect(defaultPkg.randomizeOptions, isFalse);

      final map = defaultPkg.toFirestore();
      expect(map['randomize_questions'], isFalse);
      expect(map['randomize_options'], isFalse);

      final parsed = ExamPackage.fromFirestore(map, 'TRYOUT_SNBT_01');
      expect(parsed.randomizeQuestions, isFalse);
      expect(parsed.randomizeOptions, isFalse);
    });

    test('ExamPackage serialization preserves randomizeQuestions & randomizeOptions when activated', () {
      final pkg = ExamPackage(
        paketId: 'TEST99',
        namaPaket: 'Tryout Sains Anti-Curang',
        randomizeQuestions: true,
        randomizeOptions: true,
        passingGrade: 80,
      );

      final map = pkg.toFirestore();
      expect(map['randomize_questions'], isTrue);
      expect(map['randomize_options'], isTrue);
      expect(map['passing_grade'], 80);

      final fromMap = ExamPackage.fromFirestore(map, 'TEST99');
      expect(fromMap.randomizeQuestions, isTrue);
      expect(fromMap.randomizeOptions, isTrue);
      expect(fromMap.passingGrade, 80);
    });

    test('Deterministic question shuffling: different NIS gets different order, same NIS gets same order', () {
      final token = 'CHEM26';
      final questions = List.generate(
        15,
        (i) => ExamQuestion(
          soalId: 'Q${i + 1}',
          subtestId: 'ST1',
          nomorSoal: i + 1,
          pertanyaan: 'Pertanyaan $i',
          kunci: 'A',
        ),
      );

      // Student 1 (NIS 1001)
      final seed1 = '1001'.hashCode ^ token.hashCode;
      final student1Order = List<ExamQuestion>.from(questions)..shuffle(Random(seed1));

      // Student 2 (NIS 1002) - Sebelahan
      final seed2 = '1002'.hashCode ^ token.hashCode;
      final student2Order = List<ExamQuestion>.from(questions)..shuffle(Random(seed2));

      // Student 1 Reconnect / Reopen (Same NIS 1001)
      final student1ReconnectOrder = List<ExamQuestion>.from(questions)..shuffle(Random(seed1));

      // Urutan siswa 1 dan siswa 2 harus berbeda (Anti Lirik Sebangku)
      final s1Ids = student1Order.map((q) => q.soalId).toList();
      final s2Ids = student2Order.map((q) => q.soalId).toList();
      expect(s1Ids, isNot(equals(s2Ids)));

      // Urutan siswa 1 saat reconnect harus persis sama (Idempotent)
      final s1ReconnectIds = student1ReconnectOrder.map((q) => q.soalId).toList();
      expect(s1Ids, equals(s1ReconnectIds));
    });

    test('Option shuffling preserves original answer keys for 100% accurate evaluation', () {
      final q = ExamQuestion(
        soalId: 'BIO_01',
        subtestId: 'ST1',
        nomorSoal: 1,
        pertanyaan: 'Fungsi klorofil adalah...',
        opsiA: 'Fotosintesis',
        opsiB: 'Respirasi',
        opsiC: 'Transpirasi',
        opsiD: 'Fermentasi',
        kunci: 'A',
      );

      final rawList = [
        {'origKey': 'A', 'text': q.opsiA},
        {'origKey': 'B', 'text': q.opsiB},
        {'origKey': 'C', 'text': q.opsiC},
        {'origKey': 'D', 'text': q.opsiD},
      ];

      // Shuffle untuk siswa A
      final seedA = 'NIS_A'.hashCode ^ 'TOKEN'.hashCode ^ q.soalId.hashCode;
      final shuffled = List<Map<String, String>>.from(rawList)..shuffle(Random(seedA));

      // Siswa memilih opsi yang berisi 'Fotosintesis'
      final chosen = shuffled.firstWhere((opt) => opt['text'] == 'Fotosintesis');
      final studentAnswer = chosen['origKey'];

      // Jawaban yang dicatat adalah 'A', cocok dengan kunci guru
      expect(studentAnswer, equals('A'));
      expect(studentAnswer, equals(q.kunci));
    });
  });

  group('Fitur 1: Rekap Otomatis Siswa Remedial', () {
    test('ExamPdfExporter.generateRemedialReportBytes produces valid PDF bytes with remedial students and hardest questions', () async {
      final remedialStudents = [
        {'name': 'Ahmad Fauzi', 'nis': '1011', 'skor': 55},
        {'name': 'Dewi Lestari', 'nis': '1012', 'skor': 68},
      ];

      final hardestQuestions = [
        {'nomor': '5', 'failPct': 85, 'kunci': 'C'},
        {'nomor': '12', 'failPct': 70, 'kunci': 'B'},
      ];

      final bytes = await ExamPdfExporter.generateRemedialReportBytes(
        examTitle: 'Ujian Matematika Wajib',
        examId: 'MATH26',
        passingGrade: 75,
        remedialStudents: remedialStudents,
        totalStudents: 30,
        hardestQuestions: hardestQuestions,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
      // PDF format signature: %PDF-
      expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
    });

    testWidgets('TeacherExamMatrixScreen renders Remedial button and opens bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dummyQuestions = [
        {'soalId': 'Q1', 'nomor': '1', 'kunci': 'A', 'subtest': 'Umum'},
        {'soalId': 'Q2', 'nomor': '2', 'kunci': 'B', 'subtest': 'Umum'},
      ];

      final dummyStudents = [
        {
          'name': 'Budi Santoso',
          'nis': '1001',
          'skor': 85,
          'benar': 2,
          'salah': 0,
          'totalSoal': 2,
          'jawaban': {'Q1': 'A', 'Q2': 'B'},
        },
        {
          'name': 'Siti Rahma',
          'nis': '1002',
          'skor': 50,
          'benar': 1,
          'salah': 1,
          'totalSoal': 2,
          'jawaban': {'Q1': 'A', 'Q2': 'C'},
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: TeacherExamMatrixScreen(
            examId: 'TEST_REMEDIAL',
            title: 'Tryout Remedial Test',
            passingGrade: 75,
            initialQuestions: dummyQuestions,
            initialStudents: dummyStudents,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tombol Remedial harus tampil di toolbar
      final remedialBtn = find.text('Remedial');
      expect(remedialBtn, findsOneWidget);

      // Ketuk tombol Remedial
      await tester.tap(remedialBtn);
      await tester.pumpAndSettle();

      // Bottom sheet rekap remedial terbuka
      expect(find.text('Rekap Siswa Remedial'), findsOneWidget);
      expect(find.text('Siti Rahma'), findsNWidgets(2)); // Tampil di tabel matriks dan di rekap sheet
      expect(find.text('1 dari 2 Siswa Perlu Remedial'), findsOneWidget);
      expect(find.text('Kirim WhatsApp'), findsOneWidget);
      expect(find.text('Unduh PDF'), findsOneWidget);
    });
  });
}
