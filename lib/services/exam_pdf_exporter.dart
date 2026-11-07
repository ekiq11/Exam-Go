import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Service untuk mengekspor rekapitulasi nilai ujian siswa ke format dokumen PDF resmi.
class ExamPdfExporter {
  /// Menghasilkan byte dokumen PDF laporan rekapitulasi nilai
  static Future<Uint8List> generateScoreReportBytes({
    required String examTitle,
    required String examId,
    required List<Map<String, dynamic>> scores,
    DateTime? printedAt,
  }) async {
    final pdf = pw.Document();
    final now = printedAt ?? DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final totalSubmissions = scores.length;
    final avgScore = totalSubmissions > 0
        ? (scores.fold<int>(0, (total, s) => total + (s['skor'] as int? ?? 0)) / totalSubmissions).round()
        : 0;
    final maxScore = totalSubmissions > 0 ? (scores.first['skor'] as int? ?? 0) : 0;
    final minScore = totalSubmissions > 0 ? (scores.last['skor'] as int? ?? 0) : 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ExamGO Anti-Cheat CBT',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.green800,
                        ),
                      ),
                      pw.Text(
                        'Laporan Resmi Rekapitulasi Nilai Siswa',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.green200),
                    ),
                    child: pw.Text(
                      'TOKEN: $examId',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green900,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 4),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Dicetak pada: $dateStr | Otomatis oleh Sistem ExamGO',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
              pw.Text(
                'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // Metadata Ujian
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Nama Paket / Judul Ujian:',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          examTitle,
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Total Peserta: $totalSubmissions Siswa',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Rata-Rata: $avgScore | Tertinggi: $maxScore | Terendah: $minScore',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Tabel Nilai Siswa
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['No', 'Nama Peserta', 'NIS', 'Benar', 'Salah', 'Kosong', 'Total', 'Skor Akhir'],
              headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
              headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.center,
                6: pw.Alignment.center,
                7: pw.Alignment.centerRight,
              },
              data: List.generate(scores.length, (idx) {
                final s = scores[idx];
                final total = s['totalSoal'] as int? ?? 0;
                final benar = s['benar'] as int? ?? 0;
                final salah = s['salah'] as int? ?? 0;
                final kosong = (total - benar - salah).clamp(0, total);
                return [
                  '${idx + 1}',
                  s['name']?.toString() ?? '-',
                  s['nis']?.toString() ?? '-',
                  '$benar',
                  '$salah',
                  '$kosong',
                  '$total',
                  '${s['skor'] ?? 0}',
                ];
              }),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Membuat berkas PDF, menyimpannya di direktori perangkat, dan membuka dialog download/bagikan
  static Future<File> exportAndSharePdf({
    required String examTitle,
    required String examId,
    required List<Map<String, dynamic>> scores,
  }) async {
    final bytes = await generateScoreReportBytes(
      examTitle: examTitle,
      examId: examId,
      scores: scores,
    );

    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = examTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final filePath = '${tempDir.path}/Rekap_Nilai_${sanitizedTitle}_$examId.pdf';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Rekap Nilai PDF - $examTitle',
        text: 'Laporan Rekapitulasi Nilai Siswa Ujian "$examTitle" (Token: $examId).',
      ),
    );

    return file;
  }
}
