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

  /// Menghasilkan byte dokumen PDF matriks analisis butir soal & jawaban siswa (Landscape A4)
  static Future<Uint8List> generateMatrixReportBytes({
    required String examTitle,
    required String examId,
    required List<Map<String, dynamic>> questions,
    required List<Map<String, dynamic>> students,
    DateTime? printedAt,
  }) async {
    final pdf = pw.Document();
    final now = printedAt ?? DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final totalSubmissions = students.length;
    final avgScore = totalSubmissions > 0
        ? (students.fold<int>(0, (total, s) => total + ((s['skor'] as num?)?.toInt() ?? 0)) / totalSubmissions).round()
        : 0;

    // Chunk butir soal maksimal 25 soal per halaman landscape agar tidak terpotong
    const int chunkSize = 25;
    final int totalChunks = (questions.isEmpty) ? 1 : ((questions.length + chunkSize - 1) ~/ chunkSize);

    for (int chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
      final startIdx = chunkIdx * chunkSize;
      final endIdx = (startIdx + chunkSize > questions.length) ? questions.length : startIdx + chunkSize;
      final chunkQuestions = questions.isEmpty ? <Map<String, dynamic>>[] : questions.sublist(startIdx, endIdx);

      final chunkLabel = questions.isEmpty
          ? 'Belum ada data butir soal'
          : 'Butir Soal No. ${chunkQuestions.first['nomorSoal']} s/d No. ${chunkQuestions.last['nomorSoal']} (Bagian ${chunkIdx + 1} dari $totalChunks)';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
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
                          'ExamGO CBT - Matriks Analisis Butir Soal & Jawaban Siswa',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.Text(
                          '$examTitle | $chunkLabel',
                          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Row(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.green50,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: PdfColors.green200),
                          ),
                          child: pw.Text(
                            'TOKEN: $examId',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green900,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blueGrey50,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: PdfColors.blueGrey200),
                          ),
                          child: pw.Text(
                            'Total: $totalSubmissions Siswa | Rata-rata: $avgScore',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Container(width: 10, height: 10, color: PdfColors.green100),
                    pw.SizedBox(width: 4),
                    pw.Text('Hijau = Benar', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.SizedBox(width: 12),
                    pw.Container(width: 10, height: 10, color: PdfColors.red100),
                    pw.SizedBox(width: 4),
                    pw.Text('Merah = Salah / Tidak Diisi', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.SizedBox(width: 12),
                    pw.Container(width: 10, height: 10, color: PdfColors.blueGrey800),
                    pw.SizedBox(width: 4),
                    pw.Text('Abu Gelap = Kunci Guru', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                pw.Divider(color: PdfColors.grey300, thickness: 0.8),
                pw.SizedBox(height: 2),
              ],
            );
          },
          footer: (pw.Context context) {
            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Dicetak: $dateStr | ExamGO Anti-Cheat CBT System',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            );
          },
          build: (pw.Context context) {
            // Kolom: No, Nama, NIS, Nilai, Benar, Salah, lalu Q1..Qn
            final headers = ['No', 'Nama Siswa', 'NIS', 'Nilai', 'B', 'S'];
            for (final q in chunkQuestions) {
              headers.add('Q${q['nomorSoal']}');
            }

            // Baris Kunci Jawaban
            final keyRow = ['KUNCI', 'KUNCI GURU', '-', '-', '-', '-'];
            for (final q in chunkQuestions) {
              keyRow.add(q['kunci']?.toString().toUpperCase() ?? '-');
            }

            return [
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(20),  // No
                  1: const pw.FixedColumnWidth(100), // Nama
                  2: const pw.FixedColumnWidth(48),  // NIS
                  3: const pw.FixedColumnWidth(28),  // Nilai
                  4: const pw.FixedColumnWidth(20),  // B
                  5: const pw.FixedColumnWidth(20),  // S
                  for (int i = 0; i < chunkQuestions.length; i++)
                    (6 + i): const pw.FlexColumnWidth(1),
                },
                children: [
                  // 1. Header Tabel
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.green800),
                    children: headers.map((h) {
                      return pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      );
                    }).toList(),
                  ),

                  // 2. Baris Kunci Jawaban
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    children: keyRow.map((kVal) {
                      return pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          kVal,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      );
                    }).toList(),
                  ),

                  // 3. Baris Jawaban Tiap Siswa
                  ...List.generate(students.length, (sIdx) {
                    final student = students[sIdx];
                    final rawAnswers = (student['jawaban'] as Map<String, dynamic>?) ?? {};
                    final name = student['name']?.toString() ?? '-';
                    final nis = student['nis']?.toString() ?? '-';
                    final skor = (student['skor'] as num?)?.toInt() ?? 0;
                    final benar = (student['benar'] as num?)?.toInt() ?? 0;
                    final salah = (student['salah'] as num?)?.toInt() ?? 0;
                    final isEven = sIdx % 2 == 0;

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: isEven ? PdfColors.white : PdfColors.grey50,
                      ),
                      children: [
                        // No
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text('${sIdx + 1}', style: const pw.TextStyle(fontSize: 7.5)),
                        ),
                        // Nama
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Text(
                            name,
                            maxLines: 1,
                            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        // NIS
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text(nis, style: const pw.TextStyle(fontSize: 7)),
                        ),
                        // Nilai
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            '$skor',
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              fontWeight: pw.FontWeight.bold,
                              color: skor >= 75 ? PdfColors.green900 : PdfColors.red900,
                            ),
                          ),
                        ),
                        // Benar
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text('$benar', style: const pw.TextStyle(fontSize: 7)),
                        ),
                        // Salah
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          alignment: pw.Alignment.center,
                          child: pw.Text('$salah', style: const pw.TextStyle(fontSize: 7)),
                        ),

                        // Butir Soal & Jawaban Siswa
                        ...chunkQuestions.map((q) {
                          final soalId = q['soalId']?.toString() ?? '';
                          final nomor = q['nomorSoal']?.toString() ?? '';
                          final kunci = (q['kunci']?.toString() ?? '').trim().toUpperCase();

                          // Cari jawaban siswa
                          final studentAns = (rawAnswers[soalId] ??
                                  rawAnswers[nomor] ??
                                  rawAnswers['Q$nomor'] ??
                                  '-')
                              .toString()
                              .trim()
                              .toUpperCase();

                          final isCorrect = studentAns.isNotEmpty &&
                              studentAns != '-' &&
                              kunci.isNotEmpty &&
                              studentAns == kunci;

                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 3),
                            alignment: pw.Alignment.center,
                            decoration: pw.BoxDecoration(
                              color: isCorrect ? PdfColors.green100 : PdfColors.red100,
                            ),
                            child: pw.Text(
                              studentAns.isEmpty ? '-' : studentAns,
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                fontWeight: pw.FontWeight.bold,
                                color: isCorrect ? PdfColors.green900 : PdfColors.red900,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Membuat berkas PDF Matriks Jawaban dan membagikannya via SharePlus
  static Future<File> exportAndShareMatrixPdf({
    required String examTitle,
    required String examId,
    required List<Map<String, dynamic>> questions,
    required List<Map<String, dynamic>> students,
  }) async {
    final bytes = await generateMatrixReportBytes(
      examTitle: examTitle,
      examId: examId,
      questions: questions,
      students: students,
    );

    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = examTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final filePath = '${tempDir.path}/Matriks_Jawaban_${sanitizedTitle}_$examId.pdf';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Matriks Analisis Butir Soal PDF - $examTitle',
        text: 'Laporan Matriks Analisis Butir Soal & Jawaban Siswa Ujian "$examTitle" (Token: $examId).',
      ),
    );

    return file;
  }

  /// Menghasilkan byte dokumen PDF Laporan Siswa Remedial & Analisis Soal
  static Future<Uint8List> generateRemedialReportBytes({
    required String examTitle,
    required String examId,
    required int passingGrade,
    required List<Map<String, dynamic>> remedialStudents,
    required int totalStudents,
    required List<Map<String, dynamic>> hardestQuestions,
    DateTime? printedAt,
  }) async {
    final pdf = pw.Document();
    final now = printedAt ?? DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

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
                        'Laporan Resmi Rekapitulasi Siswa Remedial & Analisis Penguatan',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.amber300),
                    ),
                    child: pw.Text(
                      'TOKEN: $examId',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.amber900,
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
            // Metadata & Ringkasan Remedial
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Mata Pelajaran / Judul Ujian:',
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
                        'KKM: $passingGrade  |  Total Peserta: $totalStudents Siswa',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Status: ${remedialStudents.length} Siswa Perlu Remedial (${totalStudents - remedialStudents.length} Tuntas)',
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: remedialStudents.isEmpty ? PdfColors.green800 : PdfColors.red800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Bagian Rekomendasi Soal Sulit
            if (hardestQuestions.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.amber300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Rekomendasi Materi Perlu Penguatan (Butir Soal Tingkat Kesalahan Tertinggi):',
                      style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900),
                    ),
                    pw.SizedBox(height: 4),
                    ...hardestQuestions.map((hq) {
                      final no = hq['nomor'] ?? '-';
                      final failPct = hq['failPct'] ?? 0;
                      final key = hq['kunci'] ?? '-';
                      return pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                        child: pw.Text(
                          '- Soal No. $no: $failPct% siswa kelas salah menjawab (Kunci Jawaban Guru: $key)',
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
            ],

            pw.Text(
              'Daftar Siswa Mengikuti Ujian Remedial:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),

            if (remedialStudents.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  'Alhamdulillah, seluruh siswa tuntas mencapai atau melampaui KKM ($passingGrade).',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                ),
              )
            else
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['No', 'Nama Siswa', 'NIS', 'Skor Akhir', 'Status', 'Catatan / Tanda Tangan'],
                headerStyle: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
                headerPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                cellStyle: const pw.TextStyle(fontSize: 8.5),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                  3: pw.Alignment.center,
                  4: pw.Alignment.center,
                  5: pw.Alignment.centerLeft,
                },
                data: List.generate(remedialStudents.length, (idx) {
                  final s = remedialStudents[idx];
                  final skor = (s['skor'] as num?)?.toInt() ?? 0;
                  return [
                    '${idx + 1}',
                    s['name']?.toString() ?? '-',
                    s['nis']?.toString() ?? '-',
                    '$skor',
                    'Remedial (< $passingGrade)',
                    '',
                  ];
                }),
              ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Membuat berkas PDF Laporan Remedial dan membagikannya via SharePlus
  static Future<File> exportAndShareRemedialPdf({
    required String examTitle,
    required String examId,
    required int passingGrade,
    required List<Map<String, dynamic>> remedialStudents,
    required int totalStudents,
    required List<Map<String, dynamic>> hardestQuestions,
  }) async {
    final bytes = await generateRemedialReportBytes(
      examTitle: examTitle,
      examId: examId,
      passingGrade: passingGrade,
      remedialStudents: remedialStudents,
      totalStudents: totalStudents,
      hardestQuestions: hardestQuestions,
    );

    final tempDir = await getTemporaryDirectory();
    final sanitizedTitle = examTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final filePath = '${tempDir.path}/Laporan_Remedial_${sanitizedTitle}_$examId.pdf';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Laporan Siswa Remedial PDF - $examTitle',
        text: 'Laporan Rekapitulasi Siswa Remedial Ujian "$examTitle" (Token: $examId).',
      ),
    );

    return file;
  }
}
