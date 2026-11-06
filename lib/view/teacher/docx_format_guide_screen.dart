import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constant/app_colors.dart';
import '../../services/docx_template_generator.dart';

/// Layar panduan lengkap format penulisan dokumen Microsoft Word (.docx)
/// untuk impor dan konversi soal otomatis di ExamGO.
class DocxFormatGuideScreen extends StatefulWidget {
  final String? initialCategory;

  const DocxFormatGuideScreen({super.key, this.initialCategory});

  @override
  State<DocxFormatGuideScreen> createState() => _DocxFormatGuideScreenState();
}

class _DocxFormatGuideScreenState extends State<DocxFormatGuideScreen> {
  bool _isDownloading = false;

  static const String _sampleDocumentText = '''[JUDUL: Try Out Mandiri 2026]
[KATEGORI: SNBT]
[JENIS_WAKTU: per_subtest]
[DURASI: 90]

[SUBTEST: Penalaran Matematika]
[DURASI_SUBTEST: 30]

1. Jika x² + 2x - 15 = 0 untuk x > 0, maka nilai dari 2x + 1 adalah...
A. 5
B. 7
C. 9
D. 11
E. 13
KUNCI: B
PEMBAHASAN: Faktorisasi (x + 5)(x - 3) = 0. Karena x > 0, maka x = 3. Nilai 2(3) + 1 = 7.

2. Diketahui segitiga siku-siku dengan panjang sisi tegak 6 cm dan 8 cm. Panjang sisi miringnya adalah...
A. 9 cm
B. 10 cm
C. 12 cm
D. 14 cm
E. 15 cm
KUNCI: B
PEMBAHASAN: Menggunakan teorema Pythagoras: c = √(6² + 8²) = √(36 + 64) = √100 = 10 cm.

[SUBTEST: Literasi Bahasa Indonesia]
[DURASI_SUBTEST: 25]

1. Gagasan utama paragraf di atas adalah...
A. Pentingnya literasi digital di era modern
B. Dampak negatif media sosial bagi remaja
C. Perkembangan teknologi kecerdasan buatan
D. Peningkatan minat baca di lingkungan sekolah
E. Pengaruh globalisasi terhadap budaya lokal
KUNCI: A
PEMBAHASAN: Paragraf memfokuskan pembahasan pada urgensi pemahaman literasi digital bagi masyarakat modern.''';

  Future<void> _downloadTemplate() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final category = widget.initialCategory ?? 'SNBT';
      final bytes = DocxTemplateGenerator.generateTemplateBytes(
        title: 'Template_Soal_ExamGO',
        category: category,
      );

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/Template_Soal_ExamGO.docx');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Template DOCX siap diunduh & diedit.',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            ),
          ],
          subject: 'Template Soal ExamGO (.docx)',
          text: 'Template Soal Ujian Microsoft Word (.docx) untuk ExamGO',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyiapkan template: $e',
                style: GoogleFonts.poppins(fontSize: 13)),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _copySampleText() {
    Clipboard.setData(const ClipboardData(text: _sampleDocumentText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Contoh format berhasil disalin ke clipboard!',
                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panduan Format Word (.docx)',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Format Penulisan Dokumen Soal Ujian',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Download Template',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Icon(Icons.download_rounded, color: AppColors.primaryGreen, size: 20),
            ),
            onPressed: _downloadTemplate,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner Ringkasan
                    _buildBannerCard(),
                    const SizedBox(height: 16),

                    // Card 1: 4 Aturan Utama
                    _buildRulesCard(),
                    const SizedBox(height: 16),

                    // Card 2: Tag Header Dokumen
                    _buildHeaderTagsCard(),
                    const SizedBox(height: 16),

                    // Card 3: Rumus & Gambar
                    _buildMathAndMediaCard(),
                    const SizedBox(height: 16),

                    // Card 4: Contoh Format Nyata
                    _buildSampleCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Sticky Bottom Button
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primaryGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ketik Alami Seperti Dokumen Biasa',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Anda tidak perlu menghafal kode rumit. Cukup ketik soal di Microsoft Word, sisipkan gambar atau rumus seperti biasa. Sistem ExamGO otomatis memproses dan menampilkannya rapi di aplikasi siswa.',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: const Color(0xFF15803D),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesCard() {
    final rules = [
      {
        'num': '1',
        'title': 'Nomor Soal Berurutan',
        'desc': 'Awali nomor soal dengan angka dan tanda titik atau kurung, contoh: "1." atau "1)".',
      },
      {
        'num': '2',
        'title': 'Pilihan Ganda A - E',
        'desc': 'Tulis opsi jawaban dengan huruf kapital diikuti titik, contoh: "A.", "B.", "C.", "D.", "E.".',
      },
      {
        'num': '3',
        'title': 'Kunci Jawaban Wajib',
        'desc': 'Cantumkan baris "KUNCI: <huruf>" di bawah opsi jawaban (contoh: KUNCI: B).',
      },
      {
        'num': '4',
        'title': 'Pembahasan (Opsional)',
        'desc': 'Tambahkan "PEMBAHASAN: <penjelasan>" agar siswa dapat membaca penjelasan setelah tryout selesai.',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded, color: AppColors.primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                'Aturan Utama Penulisan',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rules.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          r['num']!,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['title']!,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r['desc']!,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              color: const Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildHeaderTagsCard() {
    final tags = [
      {'tag': '[JUDUL: Judul Ujian]', 'desc': 'Nama paket ujian yang akan ditampilkan ke siswa.'},
      {'tag': '[KATEGORI: SNBT / SKD / TKA]', 'desc': 'Kategori untuk menentukan sistem penilaian otomatis.'},
      {'tag': '[JENIS_WAKTU: per_subtest]', 'desc': 'Pilih "per_subtest" atau "per_paket" untuk sistem timer.'},
      {'tag': '[SUBTEST: Nama Subtest]', 'desc': 'Pemisah babak/sesi soal (misal: Penalaran Matematika).'},
      {'tag': '[DURASI_SUBTEST: 30]', 'desc': 'Durasi pengerjaan khusus subtest tersebut dalam satuan menit.'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tag_rounded, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              Text(
                'Tag Konfigurasi Dokumen (Opsional)',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tag diletakkan di baris paling atas atau sebelum kumpulan soal subtest:',
            style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          ...tags.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['tag']!,
                        style: GoogleFonts.firaCode(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t['desc']!,
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMathAndMediaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.functions_rounded, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Text(
                'Rumus Matematika & Gambar Diagram',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.image_outlined,
            title: 'Sisipkan Gambar / Grafik',
            desc:
                'Cukup Paste atau Insert gambar langsung ke dalam dokumen Word. ExamGO akan mengekstrak dan mengunggah gambar otomatis ke penyimpanan awan.',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.superscript_rounded,
            title: 'Rumus Matematika & Kimia',
            desc:
                'Dapat menggunakan simbol biasa (x², √a, ½) maupun sintaks LaTeX seperti \$x^2 + 5x = 0\$. Seluruh formula dirender tajam di aplikasi siswa.',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.table_chart_outlined,
            title: 'Tabel Data',
            desc:
                'Tabel dari Word akan dikonversi menjadi tabel HTML responsif yang mudah dibaca siswa di layar ponsel.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF475569)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSampleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.code_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Contoh Teks Isi Dokumen (.docx)',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _copySampleText,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.copy_rounded, color: Color(0xFF94A3B8), size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Salin',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              _sampleDocumentText,
              style: GoogleFonts.firaCode(
                fontSize: 11,
                color: const Color(0xFFE2E8F0),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _isDownloading ? null : _downloadTemplate,
          icon: _isDownloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download_rounded, color: Colors.white, size: 20),
          label: Text(
            _isDownloading ? 'Menyiapkan Template...' : 'Download File Template (.docx)',
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}

