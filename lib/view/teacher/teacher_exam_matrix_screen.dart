import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/exam_question_model.dart';
import '../../services/exam_cache_service.dart';
import '../../services/exam_pdf_exporter.dart';
import '../student/widgets/tryout_spider_chart_widget.dart';

const Color _kDarkGreen = Color(0xFF1B5E20);
const Color _kPrimaryGreen = Color(0xFF2E7D32);
const Color _kLightGreen = Color(0xFF10B981);
const Color _kBgLight = Color(0xFFF8FAFC);
const Color _kKeyHeaderBg = Color(0xFF1E293B);

/// Layar Matriks Analisis Butir Soal & Jawaban Siswa
/// Menampilkan tabel data siswa vs seluruh butir soal dengan:
/// - Baris Kunci Jawaban Guru di atas
/// - Sel Jawaban Benar (Hijau) & Salah/Kosong (Merah)
/// - Anti-overflow untuk puluhan hingga ratusan butir soal
/// - Fitur unduh Excel (.xls berwarna) & PDF Resmi (Landscape A4)
class TeacherExamMatrixScreen extends StatefulWidget {
  final String examId;
  final String title;
  final int passingGrade;
  final List<Map<String, dynamic>>? initialQuestions;
  final List<Map<String, dynamic>>? initialStudents;
  final bool openRemedialOnStart;

  const TeacherExamMatrixScreen({
    super.key,
    required this.examId,
    required this.title,
    this.passingGrade = 75,
    this.initialQuestions,
    this.initialStudents,
    this.openRemedialOnStart = false,
  });

  @override
  State<TeacherExamMatrixScreen> createState() =>
      _TeacherExamMatrixScreenState();
}

class _TeacherExamMatrixScreenState extends State<TeacherExamMatrixScreen> {
  bool _isLoadingQuestions = true;
  String? _questionsError;
  List<Map<String, dynamic>> _questions = [];

  bool _isExportingExcel = false;
  bool _isExportingPdf = false;
  bool _isLandscape = false;
  bool _hasOpenedRemedialInitial = false;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'Semua'; // 'Semua', 'Tuntas', 'Remedial'
  bool _sortByScoreDesc = true; // true = Ranking Nilai, false = Nama A-Z

  final ScrollController _horizontalBodyScrollController = ScrollController();
  final ScrollController _horizontalHeaderScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestions != null &&
        widget.initialQuestions!.isNotEmpty) {
      _questions = List.from(widget.initialQuestions!);
      _isLoadingQuestions = false;
    } else {
      _loadQuestionsData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Kembalikan orientasi layar ke normal jika sempat diubah
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _horizontalBodyScrollController.dispose();
    _horizontalHeaderScrollController.dispose();
    super.dispose();
  }

  /// Toggle orientasi layar Landscape untuk kemudahan melihat banyak kolom soal
  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
    });

    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mode Landscape aktif: Tampilan kolom soal lebih luas.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  /// Memuat butir soal dan kunci jawaban
  Future<void> _loadQuestionsData() async {
    setState(() {
      _isLoadingQuestions = true;
      _questionsError = null;
    });

    try {
      // 1. Coba ambil dari ExamCacheService (lokal atau Firestore/GAS)
      List<ExamQuestion> qList = [];
      final cached = await ExamCacheService.instance.loadExam(widget.examId);
      if (cached != null && cached.questions.isNotEmpty) {
        qList = cached.questions;
      } else {
        try {
          final downloaded = await ExamCacheService.instance
              .downloadAndCacheExam(paketId: widget.examId);
          qList = downloaded.questions;
        } catch (_) {
          // Fallback ke query langsung Firestore
          qList = await _fetchQuestionsDirectFromFirestore();
        }
      }

      if (qList.isEmpty) {
        qList = await _fetchQuestionsDirectFromFirestore();
      }

      // Format data butir soal dan urutkan berdasarkan nomorSoal
      final formatted = qList.map((q) {
        return {
          'nomorSoal': q.nomorSoal,
          'soalId': q.soalId,
          'kunci': q.kunci.trim().toUpperCase(),
          'pertanyaan': q.pertanyaan,
        };
      }).toList();

      formatted.sort(
        (a, b) => (a['nomorSoal'] as int).compareTo(b['nomorSoal'] as int),
      );

      if (mounted) {
        setState(() {
          _questions = formatted;
          _isLoadingQuestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _questionsError = e.toString();
          _isLoadingQuestions = false;
        });
      }
    }
  }

  /// Query langsung butir soal dari Firestore jika cache lokal kosong
  Future<List<ExamQuestion>> _fetchQuestionsDirectFromFirestore() async {
    final db = FirebaseFirestore.instance;
    final tokenUpper = widget.examId.trim().toUpperCase();

    final snap = await db
        .collection('tryout_soal')
        .where('paket_id', isEqualTo: tokenUpper)
        .get()
        .timeout(const Duration(seconds: 6));

    if (snap.docs.isNotEmpty) {
      final list = snap.docs
          .map((d) => ExamQuestion.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.nomorSoal.compareTo(b.nomorSoal));
      return list;
    }

    return [];
  }

  /// Ekspor Tabel Matriks ke format Microsoft Excel (.xls) berstyling warna
  Future<void> _exportToExcel(List<Map<String, dynamic>> students) async {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data siswa untuk diekspor.')),
      );
      return;
    }

    setState(() => _isExportingExcel = true);
    try {
      final buffer = StringBuffer();
      // Tambahkan UTF-8 BOM
      buffer.write('\uFEFF');

      // Dokumen HTML Spreadsheet yang didukung penuh oleh Excel & Google Sheets
      buffer.write('''
<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<style>
  body { font-family: Calibri, Arial, sans-serif; font-size: 11pt; }
  table { border-collapse: collapse; }
  th, td { border: 1px solid #CBD5E1; padding: 6px 8px; text-align: center; }
  .title-header { font-size: 14pt; font-weight: bold; color: #1E293B; text-align: left; border: none; }
  .meta-text { font-size: 10pt; color: #475569; text-align: left; border: none; }
  .th-header { background-color: #15803D; color: #FFFFFF; font-weight: bold; text-align: center; }
  .th-header-left { background-color: #15803D; color: #FFFFFF; font-weight: bold; text-align: left; }
  .key-row { background-color: #1E293B; color: #FFFFFF; font-weight: bold; }
  .key-row-title { background-color: #1E293B; color: #FFFFFF; font-weight: bold; text-align: left; }
  .ans-correct { background-color: #D1FAE5; color: #065F46; font-weight: bold; }
  .ans-wrong { background-color: #FEE2E2; color: #991B1B; font-weight: bold; }
  .student-name { text-align: left; font-weight: bold; }
  .score-pass { color: #065F46; font-weight: bold; }
  .score-fail { color: #991B1B; font-weight: bold; }
</style>
</head>
<body>
<table>
  <tr><td colspan="${6 + _questions.length}" class="title-header">MATRIKS ANALISIS BUTIR SOAL & JAWABAN SISWA</td></tr>
  <tr><td colspan="${6 + _questions.length}" class="meta-text">Ujian: ${widget.title} | Token: ${widget.examId} | Standar KKM: ${widget.passingGrade}</td></tr>
  <tr><td colspan="${6 + _questions.length}" class="meta-text">Total Peserta: ${students.length} Siswa | Total Soal: ${_questions.length} Butir | Dicetak: ${DateTime.now().toString().substring(0, 16)}</td></tr>
  <tr><td colspan="${6 + _questions.length}" style="border:none; height:12px;"></td></tr>

  <!-- Header Kolom -->
  <tr>
    <th class="th-header" style="width: 40px;">No</th>
    <th class="th-header-left" style="width: 220px;">Nama Siswa</th>
    <th class="th-header" style="width: 100px;">NIS</th>
    <th class="th-header" style="width: 60px;">Skor</th>
    <th class="th-header" style="width: 50px;">Benar</th>
    <th class="th-header" style="width: 50px;">Salah</th>
''');

      for (final q in _questions) {
        buffer.write(
          '<th class="th-header" style="width: 45px;">Q${q['nomorSoal']}</th>',
        );
      }
      buffer.write('</tr>\n');

      // Baris Kunci Jawaban
      buffer.write('''
  <tr>
    <td class="key-row">🔑</td>
    <td class="key-row-title">KUNCI JAWABAN GURU</td>
    <td class="key-row">-</td>
    <td class="key-row">-</td>
    <td class="key-row">-</td>
    <td class="key-row">-</td>
''');
      for (final q in _questions) {
        buffer.write('<td class="key-row">${q['kunci'] ?? '-'}</td>');
      }
      buffer.write('</tr>\n');

      // Baris Jawaban Siswa
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final name = s['name']?.toString() ?? '-';
        final nis = s['nis']?.toString() ?? '-';
        final skor = (s['skor'] as num?)?.toInt() ?? 0;
        final benar = (s['benar'] as num?)?.toInt() ?? 0;
        final salah = (s['salah'] as num?)?.toInt() ?? 0;
        final rawAnswers = (s['jawaban'] as Map<String, dynamic>?) ?? {};
        final isPassed = skor >= widget.passingGrade;

        buffer.write('''
  <tr>
    <td>${i + 1}</td>
    <td class="student-name">$name</td>
    <td>$nis</td>
    <td class="${isPassed ? 'score-pass' : 'score-fail'}">$skor</td>
    <td>$benar</td>
    <td>$salah</td>
''');

        for (final q in _questions) {
          final soalId = q['soalId']?.toString() ?? '';
          final nomor = q['nomorSoal']?.toString() ?? '';
          final kunci = (q['kunci']?.toString() ?? '').trim().toUpperCase();

          final studentAns =
              (rawAnswers[soalId] ??
                      rawAnswers[nomor] ??
                      rawAnswers['Q$nomor'] ??
                      '-')
                  .toString()
                  .trim()
                  .toUpperCase();

          final isCorrect =
              studentAns.isNotEmpty &&
              studentAns != '-' &&
              kunci.isNotEmpty &&
              studentAns == kunci;

          final cssClass = isCorrect ? 'ans-correct' : 'ans-wrong';
          buffer.write(
            '<td class="$cssClass">${studentAns.isEmpty ? '-' : studentAns}</td>',
          );
        }
        buffer.write('</tr>\n');
      }

      buffer.write('''
</table>
</body>
</html>
''');

      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = widget.title
          .replaceAll(RegExp(r'[^\w\s\-]'), '_')
          .trim();
      final filePath =
          '${tempDir.path}/Matriks_Jawaban_${sanitizedTitle}_${widget.examId}.xls';
      final file = File(filePath);
      await file.writeAsString(buffer.toString(), encoding: utf8);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/vnd.ms-excel')],
          subject: 'Matriks Jawaban Excel - ${widget.title}',
          text:
              'Matriks Analisis Butir Soal Ujian "${widget.title}" (Token: ${widget.examId}).',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal mengekspor Excel: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExportingExcel = false);
    }
  }

  /// Ekspor Tabel Matriks ke dokumen PDF resmi (Landscape A4)
  Future<void> _exportToPdf(List<Map<String, dynamic>> students) async {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data siswa untuk diekspor.')),
      );
      return;
    }

    setState(() => _isExportingPdf = true);
    try {
      await ExamPdfExporter.exportAndShareMatrixPdf(
        examTitle: widget.title,
        examId: widget.examId,
        questions: _questions,
        students: students,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  /// Dialog modal bottom sheet Analisis Siswa Remedial (1-Click Remedial)
  void _showRemedialBottomSheet(List<Map<String, dynamic>> allStudents) {
    final passingGrade = widget.passingGrade;
    final remedialList = allStudents
        .where((s) => ((s['skor'] as num?)?.toInt() ?? 0) < passingGrade)
        .toList();
    // Urutkan nilai terendah dahulu
    remedialList.sort(
      (a, b) => ((a['skor'] as num?)?.toInt() ?? 0).compareTo(
        (b['skor'] as num?)?.toInt() ?? 0,
      ),
    );

    final total = allStudents.length;
    final tuntas = total - remedialList.length;

    // Hitung 3 Soal Paling Sulit (Tingkat kesalahan tertinggi) & Data Grafik Spider
    final List<Map<String, dynamic>> hardestQuestions = [];
    final List<TryoutSubScore> spiderScores = [];
    if (_questions.isNotEmpty && total > 0) {
      final qStats = <Map<String, dynamic>>[];
      for (final q in _questions) {
        final qId = q['soalId']?.toString() ?? '';
        final qNomor =
            q['nomor']?.toString() ?? q['nomorSoal']?.toString() ?? '0';
        final qKunci = q['kunci']?.toString() ?? '-';

        int wrongCount = 0;
        for (final s in allStudents) {
          final answers = (s['jawaban'] as Map<String, dynamic>?) ?? {};
          final ans = answers[qId]?.toString().toUpperCase() ?? '';
          if (ans != qKunci) {
            wrongCount++;
          }
        }
        final failPct = ((wrongCount / total) * 100).round();
        qStats.add({
          'nomor': qNomor,
          'soalId': qId,
          'kunci': qKunci,
          'wrongCount': wrongCount,
          'failPct': failPct,
        });
      }
      qStats.sort(
        (a, b) => (b['failPct'] as int).compareTo(a['failPct'] as int),
      );
      hardestQuestions.addAll(qStats.take(3));

      // Siapkan minimal 3 sumbu untuk Spider Chart (polygon membutuhkan >= 3 sudut)
      final chartQuestions = qStats.length >= 3
          ? qStats.take(math.min(6, qStats.length)).toList()
          : qStats;
      if (chartQuestions.length >= 3) {
        for (final hq in chartQuestions) {
          final fail = (hq['failPct'] as int).toDouble();
          final mastery = (100.0 - fail).clamp(0.0, 100.0);
          final wrong = hq['wrongCount'] as int;
          final correct = total - wrong;
          final color = mastery < 50
              ? const Color(0xFFDC2626)
              : (mastery < 75
                    ? const Color(0xFFD97706)
                    : const Color(0xFF16A34A));
          spiderScores.add(
            TryoutSubScore(
              name: 'No. ${hq['nomor']}',
              score: mastery,
              maxValue: 100.0,
              totalBenar: correct,
              totalSoal: total,
              color: color,
            ),
          );
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.assignment_late_rounded,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rekap Siswa Remedial',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${widget.title} • KKM: $passingGrade',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content Body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Summary Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: remedialList.isEmpty
                              ? [
                                  const Color(0xFFF0FDF4),
                                  const Color(0xFFDCFCE7),
                                ]
                              : [
                                  const Color(0xFFFFFBEB),
                                  const Color(0xFFFEF3C7),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: remedialList.isEmpty
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFCD34D),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            remedialList.isEmpty
                                ? Icons.verified_rounded
                                : Icons.info_outline_rounded,
                            color: remedialList.isEmpty
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  remedialList.isEmpty
                                      ? 'Luar Biasa! Seluruh Siswa Tuntas'
                                      : '${remedialList.length} dari $total Siswa Perlu Remedial',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: remedialList.isEmpty
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tuntas KKM (≥ $passingGrade): $tuntas siswa • Remedial (< $passingGrade): ${remedialList.length} siswa',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: remedialList.isEmpty
                                        ? const Color(0xFF166534)
                                        : const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Top Soal Paling Sulit & Grafik Spider Butir Soal Penguatan
                    if (hardestQuestions.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.psychology_alt_rounded,
                            size: 16,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Soal Perlu Penguatan (Kesalahan Tertinggi):',
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Grafik Spider Analisis Soal Penguatan
                      if (spiderScores.length >= 3) ...[
                        TryoutSpiderChartWidget(
                          subScores: spiderScores,
                          title: 'Grafik Penguasaan Butir Soal',
                          subtitle:
                              'Persentase ketercapaian kelas per nomor soal',
                          height: 220,
                          showLegend: true,
                        ),
                        const SizedBox(height: 10),
                      ],

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: hardestQuestions.map((hq) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFDC2626,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Q${hq['nomor']}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${hq['failPct']}% siswa kelas salah • Kunci Guru: [${hq['kunci']}]',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11.5,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Daftar Siswa Remedial
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Daftar Siswa Remedial:',
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        Text(
                          'Urut Skor Terendah',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (remedialList.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 40,
                              color: Color(0xFF16A34A),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tidak ada siswa yang perlu remedial!',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(remedialList.length, (idx) {
                        final s = remedialList[idx];
                        final name = s['name']?.toString() ?? '-';
                        final nis = s['nis']?.toString() ?? '-';
                        final skor = (s['skor'] as num?)?.toInt() ?? 0;
                        final benar = (s['benar'] as num?)?.toInt() ?? 0;
                        final totalQ =
                            (s['totalSoal'] as num?)?.toInt() ??
                            _questions.length;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFEE2E2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'NIS: $nis • Benar: $benar dari $totalQ soal',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.5,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFFECACA),
                                  ),
                                ),
                                child: Text(
                                  '$skor',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),

              // Bottom Action Bar: Bagikan WA & Unduh PDF (Modern Redesign)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(
                    top: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Tombol Bagikan WhatsApp Modern Redesign
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF128C7E,
                              ).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _shareRemedialWhatsApp(
                                remedialList,
                                total,
                                hardestQuestions,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.chat_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Kirim WhatsApp',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Tombol Unduh PDF Remedial Modern Redesign
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE11D48), Color(0xFFBE123C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFBE123C,
                              ).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.pop(ctx);
                              _exportRemedialPdf(
                                remedialList,
                                total,
                                hardestQuestions,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Unduh PDF',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _shareRemedialWhatsApp(
    List<Map<String, dynamic>> remedialStudents,
    int totalStudents,
    List<Map<String, dynamic>> hardestQuestions,
  ) {
    final passingGrade = widget.passingGrade;
    final buffer = StringBuffer();
    buffer.writeln('📢 *PENGUMUMAN SISWA REMEDIAL & EVALUASI UJIAN*');
    buffer.writeln('📚 *Ujian:* ${widget.title}');
    buffer.writeln('🔑 *Token:* ${widget.examId}');
    buffer.writeln('🎯 *Standar KKM:* $passingGrade');
    buffer.writeln(
      '📊 *Hasil:* ${remedialStudents.length} siswa remedial dari $totalStudents siswa',
    );
    buffer.writeln('');

    if (remedialStudents.isEmpty) {
      buffer.writeln(
        '✅ *Selamat! Seluruh siswa telah tuntas mencapai/melampaui nilai KKM.*',
      );
    } else {
      buffer.writeln('⚠️ *Daftar Siswa Perlu Remedial:*');
      for (int i = 0; i < remedialStudents.length; i++) {
        final s = remedialStudents[i];
        final name = s['name'] ?? '-';
        final nis = s['nis'] ?? '-';
        final skor = s['skor'] ?? 0;
        buffer.writeln('${i + 1}. $name (NIS: $nis) — Nilai: $skor');
      }
    }

    if (hardestQuestions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln(
        '💡 *Topik / Butir Soal Terbanyak Salah (Perlu Penguatan):*',
      );
      for (final hq in hardestQuestions) {
        buffer.writeln(
          '• Soal ${hq['nomor']}: ${hq['failPct']}% siswa salah (Kunci: ${hq['kunci']})',
        );
      }
    }

    buffer.writeln('');
    buffer.writeln('_Laporan otomatis dari ExamGo CBT Dashboard Guru_');

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Daftar Siswa Remedial - ${widget.title}',
      ),
    );
  }

  Future<void> _exportRemedialPdf(
    List<Map<String, dynamic>> remedialStudents,
    int totalStudents,
    List<Map<String, dynamic>> hardestQuestions,
  ) async {
    setState(() => _isExportingPdf = true);
    try {
      await ExamPdfExporter.exportAndShareRemedialPdf(
        examTitle: widget.title,
        examId: widget.examId,
        passingGrade: widget.passingGrade,
        remedialStudents: remedialStudents,
        totalStudents: totalStudents,
        hardestQuestions: hardestQuestions,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat PDF Remedial: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  /// Dialog detail jawaban 1 siswa saat sel diklik
  void _showStudentDetailBottomSheet(Map<String, dynamic> student) {
    final name = student['name']?.toString() ?? '-';
    final nis = student['nis']?.toString() ?? '-';
    final skor = (student['skor'] as num?)?.toInt() ?? 0;
    final benar = (student['benar'] as num?)?.toInt() ?? 0;
    final salah = (student['salah'] as num?)?.toInt() ?? 0;
    final total = (student['totalSoal'] as num?)?.toInt() ?? _questions.length;
    final kosong = (total - benar - salah).clamp(0, total);
    final rawAnswers = (student['jawaban'] as Map<String, dynamic>?) ?? {};
    final isPassed = skor >= widget.passingGrade;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Header Profil Siswa
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isPassed
                          ? _kLightGreen.withValues(alpha: 0.15)
                          : Colors.red.shade50,
                      child: Icon(
                        isPassed
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: isPassed ? _kPrimaryGreen : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'NIS: $nis | Status: ${isPassed ? 'TUNTAS' : 'REMEDIAL'}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: isPassed
                                  ? _kPrimaryGreen
                                  : Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Skor $skor',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isPassed
                              ? const Color(0xFF065F46)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Ringkasan Jawaban
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatMiniBadge(
                      'Benar: $benar',
                      const Color(0xFFD1FAE5),
                      const Color(0xFF065F46),
                    ),
                    const SizedBox(width: 8),
                    _buildStatMiniBadge(
                      'Salah: $salah',
                      const Color(0xFFFEE2E2),
                      const Color(0xFF991B1B),
                    ),
                    const SizedBox(width: 8),
                    _buildStatMiniBadge(
                      'Kosong: $kosong',
                      Colors.grey.shade200,
                      Colors.grey.shade800,
                    ),
                  ],
                ),
              ),

              const Divider(height: 24),

              // Daftar Butir Soal & Jawaban
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: _questions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final q = _questions[idx];
                    final nomor = q['nomorSoal'];
                    final soalId = q['soalId']?.toString() ?? '';
                    final kunci = (q['kunci']?.toString() ?? '')
                        .trim()
                        .toUpperCase();

                    final studentAns =
                        (rawAnswers[soalId] ??
                                rawAnswers['$nomor'] ??
                                rawAnswers['Q$nomor'] ??
                                '-')
                            .toString()
                            .trim()
                            .toUpperCase();

                    final isCorrect =
                        studentAns.isNotEmpty &&
                        studentAns != '-' &&
                        kunci.isNotEmpty &&
                        studentAns == kunci;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$nomor',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Kunci: $kunci',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Jawab: ${studentAns.isEmpty ? '-' : studentAns} ${isCorrect ? '✓' : '✗'}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isCorrect
                                    ? const Color(0xFF065F46)
                                    : const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatMiniBadge(String text, Color bg, Color textCol) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: textCol,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _kDarkGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Matriks & Analisis Jawaban',
              style: GoogleFonts.poppins(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '${widget.title} • Token: ${widget.examId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Tombol Putar Layar (Landscape / Portrait)
          IconButton(
            tooltip: _isLandscape
                ? 'Kembali ke Potret'
                : 'Mode Layar Luas (Landscape)',
            icon: Icon(
              _isLandscape
                  ? Icons.stay_current_portrait_rounded
                  : Icons.screen_rotation_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: _toggleOrientation,
          ),
        ],
      ),
      body: _isLoadingQuestions
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _kLightGreen),
                  SizedBox(height: 14),
                  Text('Memuat butir soal & kunci ujian...'),
                ],
              ),
            )
          : _questionsError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gagal Memuat Soal Ujian',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _questionsError!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadQuestionsData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : widget.initialStudents != null
          ? _buildMatrixContent(widget.initialStudents!)
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('jawaban_tryout')
                  .where('token', isEqualTo: widget.examId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _kLightGreen),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                final List<Map<String, dynamic>> allStudents = docs.map((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return {
                    'name': data['nama_peserta']?.toString() ?? 'Anonim',
                    'nis': data['nis']?.toString() ?? '-',
                    'skor': (data['skor_akhir'] as num?)?.toInt() ?? 0,
                    'benar': (data['jumlah_benar'] as num?)?.toInt() ?? 0,
                    'salah': (data['jumlah_salah'] as num?)?.toInt() ?? 0,
                    'totalSoal':
                        (data['total_soal'] as num?)?.toInt() ??
                        _questions.length,
                    'jawaban': (data['jawaban'] as Map<String, dynamic>?) ?? {},
                    'submittedAt': data['submitted_at'],
                  };
                }).toList();

                return _buildMatrixContent(allStudents);
              },
            ),
    );
  }

  /// Membangun seluruh konten toolbar, filter, dan tabel matriks siswa
  Widget _buildMatrixContent(List<Map<String, dynamic>> allStudents) {
    final list = List<Map<String, dynamic>>.from(allStudents);

    // Pengurutan: Peringkat Skor Tertinggi vs Nama A-Z
    if (_sortByScoreDesc) {
      list.sort(
        (a, b) => ((b['skor'] as num?)?.toInt() ?? 0).compareTo(
          (a['skor'] as num?)?.toInt() ?? 0,
        ),
      );
    } else {
      list.sort(
        (a, b) => (a['name']?.toString() ?? '').toLowerCase().compareTo(
          (b['name']?.toString() ?? '').toLowerCase(),
        ),
      );
    }

    // Filter pencarian dan status KKM
    final filteredStudents = list.where((s) {
      final name = (s['name']?.toString() ?? '').toLowerCase();
      final nis = (s['nis']?.toString() ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();
      final matchQuery = q.isEmpty || name.contains(q) || nis.contains(q);

      final skor = (s['skor'] as num?)?.toInt() ?? 0;
      final isPassed = skor >= widget.passingGrade;

      if (_selectedFilter == 'Tuntas') {
        return matchQuery && isPassed;
      } else if (_selectedFilter == 'Remedial') {
        return matchQuery && !isPassed;
      }
      return matchQuery;
    }).toList();

    if (widget.openRemedialOnStart &&
        !_hasOpenedRemedialInitial &&
        allStudents.isNotEmpty &&
        !_isLoadingQuestions) {
      _hasOpenedRemedialInitial = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRemedialBottomSheet(allStudents);
      });
    }

    return Column(
      children: [
        // ── Toolbar Atas: Action Download & Search Bar Elegan ──
        _buildTopToolbar(list, filteredStudents),

        // ── Legenda Warna, Filter Status & Sort ──
        _buildLegendAndFilterBar(list),

        // ── Tabel Matriks Utama (Anti Overflow) ──
        Expanded(
          child: filteredStudents.isEmpty
              ? _buildEmptyState()
              : _buildMatrixGrid(filteredStudents),
        ),
      ],
    );
  }

  /// Toolbar atas: Tombol Download & Baris Pencarian Elegan & User-friendly
  Widget _buildTopToolbar(
    List<Map<String, dynamic>> allStudents,
    List<Map<String, dynamic>> filteredStudents,
  ) {
    final bool isSearching = _searchQuery.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.8),
        ),
      ),
      child: Column(
        children: [
          // ── Baris 1: Status Jumlah Siswa (Kiri) & Tombol Aksi Remedial, Excel, PDF (Kanan) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Total Siswa (Sebelah Kiri)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isSearching
                        ? const Color(0xFFE0F2FE)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSearching
                          ? const Color(0xFF7DD3FC)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSearching
                            ? Icons.person_search_rounded
                            : Icons.people_alt_rounded,
                        size: 13,
                        color: isSearching
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isSearching
                              ? '${filteredStudents.length} dari ${allStudents.length} Siswa'
                              : '${allStudents.length} Siswa',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isSearching
                                ? const Color(0xFF0369A1)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Tombol Remedial, Excel, PDF (Sebelah Kanan)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tombol Rekap Remedial
                  ElevatedButton.icon(
                    onPressed: () => _showRemedialBottomSheet(allStudents),
                    icon: const Icon(
                      Icons.assignment_late_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Remedial',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  // Tombol Download Excel
                  ElevatedButton.icon(
                    onPressed: (_isExportingExcel || _isExportingPdf)
                        ? null
                        : () => _exportToExcel(allStudents),
                    icon: _isExportingExcel
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.table_view_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isExportingExcel ? 'Excel...' : 'Excel',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),

                  // Tombol Download PDF
                  ElevatedButton.icon(
                    onPressed: (_isExportingExcel || _isExportingPdf)
                        ? null
                        : () => _exportToPdf(allStudents),
                    icon: _isExportingPdf
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isExportingPdf ? 'PDF...' : 'PDF',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Baris 2: Search Bar Full Width Elegan ──
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSearching
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFE2E8F0),
                width: isSearching ? 1.4 : 1.0,
              ),
              boxShadow: [
                if (isSearching)
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isSearching
                      ? const Color(0xFF0F766E)
                      : Colors.grey.shade400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Cari nama siswa atau NIS...',
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                    tooltip: 'Hapus Pencarian',
                    splashRadius: 18,
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Legenda warna, filter chip status, dan tombol pengurutan (Ranking / A-Z)
  Widget _buildLegendAndFilterBar(List<Map<String, dynamic>> allStudents) {
    final passedCount = allStudents
        .where((s) => (s['skor'] as int) >= widget.passingGrade)
        .length;
    final remedialCount = allStudents.length - passedCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // Legenda Warna
            _buildLegendPill(
              '🟢 Benar',
              const Color(0xFFD1FAE5),
              const Color(0xFF065F46),
            ),
            const SizedBox(width: 6),
            _buildLegendPill(
              '🔴 Salah/Kosong',
              const Color(0xFFFEE2E2),
              const Color(0xFF991B1B),
            ),
            const SizedBox(width: 6),
            _buildLegendPill('🔑 Kunci Guru', _kKeyHeaderBg, Colors.white),
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: Colors.grey.shade300),
            const SizedBox(width: 12),

            // Filter Chips Status KKM
            _buildFilterChip('Semua (${allStudents.length})', 'Semua'),
            const SizedBox(width: 6),
            _buildFilterChip('Tuntas ($passedCount)', 'Tuntas'),
            const SizedBox(width: 6),
            _buildFilterChip('Remedial ($remedialCount)', 'Remedial'),

            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: Colors.grey.shade300),
            const SizedBox(width: 12),

            // Tombol Pengurutan (Ranking vs Nama A-Z)
            InkWell(
              onTap: () => setState(() => _sortByScoreDesc = !_sortByScoreDesc),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      _sortByScoreDesc
                          ? Icons.trending_down_rounded
                          : Icons.sort_by_alpha_rounded,
                      size: 13,
                      color: const Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sortByScoreDesc ? 'Ranking ↓' : 'Nama A-Z ↑',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendPill(String label, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textCol,
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? _kPrimaryGreen : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  /// Tampilan Matriks Dua Dimensi (Terkunci vertikal & scroll horizontal)
  Widget _buildMatrixGrid(List<Map<String, dynamic>> students) {
    const double colWidthLeft = 145.0;
    const double colWidthQuestion = 44.0;
    const double rowHeight = 48.0;
    const double headerHeight = 42.0;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KOLOM KIRI (Terpancang / Fixed): Siswa, Kunci, Nilai ──
          SizedBox(
            width: colWidthLeft,
            child: Column(
              children: [
                // 1. Header Kolom Kiri
                Container(
                  height: headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: const BoxDecoration(
                    color: _kDarkGreen,
                    border: Border(
                      bottom: BorderSide(color: Colors.white24, width: 1),
                      right: BorderSide(color: Colors.white24, width: 1),
                    ),
                  ),
                  child: Text(
                    'No & Siswa',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),

                // 2. Baris KUNCI JAWABAN GURU
                Container(
                  height: rowHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _kKeyHeaderBg,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade400, width: 1),
                      right: BorderSide(color: Colors.grey.shade400, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('🔑', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'KUNCI GURU',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Baris Siswa
                ...List.generate(students.length, (sIdx) {
                  final s = students[sIdx];
                  final name = s['name']?.toString() ?? '-';
                  final nis = s['nis']?.toString() ?? '-';
                  final skor = (s['skor'] as num?)?.toInt() ?? 0;
                  final isPassed = skor >= widget.passingGrade;
                  final isEven = sIdx % 2 == 0;

                  return InkWell(
                    onTap: () => _showStudentDetailBottomSheet(s),
                    child: Container(
                      height: rowHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isEven ? Colors.white : const Color(0xFFF1F5F9),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade300,
                            width: 0.5,
                          ),
                          right: BorderSide(
                            color: Colors.grey.shade400,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${sIdx + 1}.',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      nis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 9.5,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPassed
                                            ? const Color(0xFFD1FAE5)
                                            : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '$skor',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isPassed
                                              ? const Color(0xFF065F46)
                                              : const Color(0xFF991B1B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // ── GRID KANAN (Scrollable Horizontal): Kolom Q01, Q02 ... Qn ──
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalBodyScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: _questions.length * colWidthQuestion,
                child: Column(
                  children: [
                    // 1. Header Nomor Soal
                    Container(
                      height: headerHeight,
                      decoration: const BoxDecoration(
                        color: _kDarkGreen,
                        border: Border(
                          bottom: BorderSide(color: Colors.white24, width: 1),
                        ),
                      ),
                      child: Row(
                        children: _questions.map((q) {
                          return Container(
                            width: colWidthQuestion,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Colors.white12,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              'Q${q['nomorSoal']}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // 2. Baris Kunci Jawaban Soal
                    Container(
                      height: rowHeight,
                      decoration: BoxDecoration(
                        color: _kKeyHeaderBg,
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade400,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: _questions.map((q) {
                          final kunci = q['kunci']?.toString() ?? '-';
                          return Container(
                            width: colWidthQuestion,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Colors.grey.shade700,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                kunci,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // 3. Baris Jawaban Tiap Siswa
                    ...List.generate(students.length, (sIdx) {
                      final s = students[sIdx];
                      final rawAnswers =
                          (s['jawaban'] as Map<String, dynamic>?) ?? {};
                      final isEven = sIdx % 2 == 0;

                      return InkWell(
                        onTap: () => _showStudentDetailBottomSheet(s),
                        child: Container(
                          height: rowHeight,
                          decoration: BoxDecoration(
                            color: isEven
                                ? Colors.white
                                : const Color(0xFFF1F5F9),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: _questions.map((q) {
                              final soalId = q['soalId']?.toString() ?? '';
                              final nomor = q['nomorSoal']?.toString() ?? '';
                              final kunci = (q['kunci']?.toString() ?? '')
                                  .trim()
                                  .toUpperCase();

                              final studentAns =
                                  (rawAnswers[soalId] ??
                                          rawAnswers[nomor] ??
                                          rawAnswers['Q$nomor'] ??
                                          '-')
                                      .toString()
                                      .trim()
                                      .toUpperCase();

                              final isCorrect =
                                  studentAns.isNotEmpty &&
                                  studentAns != '-' &&
                                  kunci.isNotEmpty &&
                                  studentAns == kunci;

                              return Container(
                                width: colWidthQuestion,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isCorrect
                                        ? const Color(0xFFD1FAE5)
                                        : const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    studentAns.isEmpty ? '-' : studentAns,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isCorrect
                                          ? const Color(0xFF065F46)
                                          : const Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearching = _searchQuery.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearching
                    ? Icons.person_search_rounded
                    : Icons.search_off_rounded,
                size: 38,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isSearching
                  ? 'Siswa "$_searchQuery" Tidak Ditemukan'
                  : 'Belum Ada Data Siswa',
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isSearching
                  ? 'Periksa kembali penulisan nama atau nomor induk siswa (NIS).'
                  : 'Siswa yang telah mengumpulkan jawaban ujian akan otomatis tampil di sini.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (isSearching) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Reset Pencarian',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
