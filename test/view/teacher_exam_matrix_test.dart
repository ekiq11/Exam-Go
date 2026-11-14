import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/exam_pdf_exporter.dart';
import 'package:examgo/view/teacher/teacher_exam_matrix_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamPdfExporter Matrix Report Unit Tests', () {
    test('generateMatrixReportBytes produces valid PDF bytes for 30 questions', () async {
      final questions = List.generate(30, (i) => {
        'nomorSoal': i + 1,
        'soalId': 'Q_${i + 1}',
        'kunci': i % 2 == 0 ? 'A' : 'C',
      });

      final students = [
        {
          'name': 'Ahmad Fauzi',
          'nis': '1001',
          'skor': 90,
          'benar': 27,
          'salah': 3,
          'totalSoal': 30,
          'jawaban': {
            for (int i = 0; i < 30; i++)
              'Q_${i + 1}': i == 2 ? 'B' : (i % 2 == 0 ? 'A' : 'C'),
          },
        },
        {
          'name': 'Siti Rahma',
          'nis': '1002',
          'skor': 60,
          'benar': 18,
          'salah': 12,
          'totalSoal': 30,
          'jawaban': {
            for (int i = 0; i < 30; i++)
              'Q_${i + 1}': i < 18 ? (i % 2 == 0 ? 'A' : 'C') : 'D',
          },
        },
      ];

      final bytes = await ExamPdfExporter.generateMatrixReportBytes(
        examTitle: 'Penilaian Harian Matematika',
        examId: 'YH55TD',
        questions: questions,
        students: students,
      );

      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
      // PDF header standard %PDF-
      expect(String.fromCharCodes(bytes.take(5)), contains('%PDF'));
    });
  });

  group('TeacherExamMatrixScreen Widget Tests', () {
    testWidgets('renders matrix screen toolbar, legend, and action buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testQuestions = List.generate(5, (i) => {
        'nomorSoal': i + 1,
        'soalId': 'Q_${i + 1}',
        'kunci': 'A',
      });

      final testStudents = [
        {
          'name': 'Ahmad Fauzi',
          'nis': '1001',
          'skor': 80,
          'benar': 4,
          'salah': 1,
          'totalSoal': 5,
          'jawaban': {
            'Q_1': 'A',
            'Q_2': 'A',
            'Q_3': 'B',
            'Q_4': 'A',
            'Q_5': 'A',
          },
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: TeacherExamMatrixScreen(
            examId: 'TEST99',
            title: 'Tryout Biologi Mandiri',
            passingGrade: 75,
            initialQuestions: testQuestions,
            initialStudents: testStudents,
          ),
        ),
      );

      // Pastikan AppBar ter-render
      expect(find.text('Matriks & Analisis Jawaban'), findsOneWidget);
      expect(find.textContaining('TEST99'), findsOneWidget);

      await tester.pump();

      // Pastikan tombol Excel & PDF tersedia
      expect(find.text('Excel'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);

      // Pastikan legenda warna ada
      expect(find.text('🟢 Benar'), findsOneWidget);
      expect(find.text('🔴 Salah/Kosong'), findsOneWidget);
      expect(find.text('🔑 Kunci Guru'), findsOneWidget);

      // Pastikan siswa dan kunci guru ditampilkan di tabel matriks
      expect(find.text('Ahmad Fauzi'), findsOneWidget);
      expect(find.text('KUNCI GURU'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);

      // Tap pada baris siswa untuk membuka bottom sheet detail
      await tester.tap(find.text('Ahmad Fauzi'));
      await tester.pumpAndSettle();

      // Pastikan BottomSheet detail siswa muncul dengan statistik
      expect(find.text('Benar: 4'), findsOneWidget);
      expect(find.text('Salah: 1'), findsOneWidget);
      expect(find.textContaining('TUNTAS'), findsOneWidget);
    });
  });
}
