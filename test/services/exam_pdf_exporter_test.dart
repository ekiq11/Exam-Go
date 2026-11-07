import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:examgo/services/exam_pdf_exporter.dart';

void main() {
  group('ExamPdfExporter Tests', () {
    test('generateScoreReportBytes produces valid PDF bytes', () async {
      final sampleScores = [
        {
          'rank': 1,
          'name': 'Ahmad Fauzi',
          'nis': '1001',
          'skor': 95,
          'benar': 19,
          'salah': 1,
          'totalSoal': 20,
        },
        {
          'rank': 2,
          'name': 'Siti Nurhaliza',
          'nis': '1002',
          'skor': 85,
          'benar': 17,
          'salah': 3,
          'totalSoal': 20,
        },
      ];

      final bytes = await ExamPdfExporter.generateScoreReportBytes(
        examTitle: 'Penilaian Akhir Semester Ganjil',
        examId: 'PAS2026',
        scores: sampleScores,
        printedAt: DateTime(2026, 11, 7, 10, 30),
      );

      expect(bytes, isNotEmpty);
      // Valid PDF documents start with '%PDF-'
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generateScoreReportBytes handles empty score list safely', () async {
      final bytes = await ExamPdfExporter.generateScoreReportBytes(
        examTitle: 'Tryout Mandiri',
        examId: 'TRY999',
        scores: [],
      );

      expect(bytes, isNotEmpty);
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });
  });
}
