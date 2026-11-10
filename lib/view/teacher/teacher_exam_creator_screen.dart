import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constant/app_colors.dart';
import '../../models/exam_question_model.dart';
import '../../services/docx_exam_parser.dart';
import '../../services/docx_template_generator.dart';
import '../../services/gform_exam_parser.dart';
import '../../services/license_service.dart';
import '../widgets/premium_token_dialog.dart';
import '../widgets/app_back_button.dart';
import 'docx_format_guide_screen.dart';
import 'teacher_exam_preview_screen.dart';

class TeacherExamCreatorScreen extends StatefulWidget {
  const TeacherExamCreatorScreen({super.key});

  @override
  State<TeacherExamCreatorScreen> createState() =>
      _TeacherExamCreatorScreenState();
}

class _TeacherExamCreatorScreenState extends State<TeacherExamCreatorScreen>
    with SingleTickerProviderStateMixin {
  // Stepper aktif (0: Informasi & Kategori, 1: Alokasi Subtest, 2: Impor & Konversi)
  int _currentStep = 0;

  late TabController _sourceTabController;
  int _selectedSourceTab =
      1; // 0: Word .docx, 1: Google Form (Default Google Form sebagai rekomendasi utama)

  final _titleController = TextEditingController(text: 'Try Out Akbar 2026');
  final _gformUrlController = TextEditingController();
  final _durationController = TextEditingController(text: '90');

  String _selectedCategory = ExamCategory.snbt;
  String _jenisWaktu = 'per_subtest'; // 'per_subtest' atau 'per_paket'

  // Daftar subtest yang dapat diatur secara fleksibel oleh guru
  List<ExamSubtest> _subtests = [];

  bool _isLoading = false;
  String _loadingStatus = '';
  double _loadingProgress = 0.0;

  DocxParseResult? _docxResult;
  GFormParseResult? _gformResult;
  ExamPackage? _currentPackage;

  String? _pickedFileName;
  int? _pickedFileSize;
  bool _isDownloadingTemplate = false;

  bool _isTeacherPremium = false;
  int _remainingUploads = 3;
  bool _hasLoadedLicense = false;

  @override
  void initState() {
    super.initState();
    _sourceTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 1,
    );
    _applyCategoryPreset(_selectedCategory);
    _loadTeacherLicenseStatus();
  }

  Future<void> _loadTeacherLicenseStatus() async {
    final isPrem = await LicenseService.instance.isTeacherPremium();
    final rem = await LicenseService.instance.getRemainingTeacherUploads();
    if (mounted) {
      setState(() {
        _isTeacherPremium = isPrem;
        _remainingUploads = rem;
        _hasLoadedLicense = true;
      });
    }
  }

  @override
  void dispose() {
    _sourceTabController.dispose();
    _titleController.dispose();
    _gformUrlController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  // ─── Preset Kategori & Alokasi Subtest ────────────────────────
  void _applyCategoryPreset(String category) {
    setState(() {
      _selectedCategory = category;
      _subtests.clear();

      switch (category) {
        case ExamCategory.snbt:
          _jenisWaktu = 'per_subtest';
          _durationController.text = '210';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Penalaran Umum',
              durasiMenit: 30,
            ),
            ExamSubtest(
              subtestId: 'ST2',
              paketId: '',
              judul: 'Pengetahuan & Pemahaman Umum (PPU)',
              durasiMenit: 15,
            ),
            ExamSubtest(
              subtestId: 'ST3',
              paketId: '',
              judul: 'Pemahaman Bacaan & Menulis (PBM)',
              durasiMenit: 25,
            ),
            ExamSubtest(
              subtestId: 'ST4',
              paketId: '',
              judul: 'Pengetahuan Kuantitatif',
              durasiMenit: 20,
            ),
            ExamSubtest(
              subtestId: 'ST5',
              paketId: '',
              judul: 'Literasi Bahasa Indonesia',
              durasiMenit: 40,
            ),
            ExamSubtest(
              subtestId: 'ST6',
              paketId: '',
              judul: 'Literasi Bahasa Inggris',
              durasiMenit: 40,
            ),
            ExamSubtest(
              subtestId: 'ST7',
              paketId: '',
              judul: 'Penalaran Matematika',
              durasiMenit: 40,
            ),
          ];
          break;

        case ExamCategory.skd:
          _jenisWaktu = 'per_paket';
          _durationController.text = '100';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Tes Wawasan Kebangsaan (TWK)',
              durasiMenit: 30,
            ),
            ExamSubtest(
              subtestId: 'ST2',
              paketId: '',
              judul: 'Tes Intelegensia Umum (TIU)',
              durasiMenit: 35,
            ),
            ExamSubtest(
              subtestId: 'ST3',
              paketId: '',
              judul: 'Tes Karakteristik Pribadi (TKP)',
              durasiMenit: 35,
            ),
          ];
          break;

        case ExamCategory.tkaSma:
          _jenisWaktu = 'per_subtest';
          _durationController.text = '225';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Matematika',
              durasiMenit: 75,
            ),
            ExamSubtest(
              subtestId: 'ST2',
              paketId: '',
              judul: 'Bahasa Indonesia',
              durasiMenit: 75,
            ),
            ExamSubtest(
              subtestId: 'ST3',
              paketId: '',
              judul: 'Bahasa Inggris',
              durasiMenit: 75,
            ),
          ];
          break;

        case ExamCategory.tkaSmp:
          _jenisWaktu = 'per_subtest';
          _durationController.text = '120';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Matematika',
              durasiMenit: 60,
            ),
            ExamSubtest(
              subtestId: 'ST2',
              paketId: '',
              judul: 'Bahasa Indonesia',
              durasiMenit: 60,
            ),
          ];
          break;

        case ExamCategory.tkaSd:
          _jenisWaktu = 'per_subtest';
          _durationController.text = '90';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Matematika',
              durasiMenit: 45,
            ),
            ExamSubtest(
              subtestId: 'ST2',
              paketId: '',
              judul: 'Bahasa Indonesia',
              durasiMenit: 45,
            ),
          ];
          break;

        case ExamCategory.umum:
        default:
          _jenisWaktu = 'per_paket';
          _durationController.text = '90';
          _subtests = [
            ExamSubtest(
              subtestId: 'ST1',
              paketId: '',
              judul: 'Soal Ujian',
              durasiMenit: 90,
            ),
          ];
          break;
      }
    });
  }

  // ─── Download Template DOCX Standar ───────────────────────────
  Future<void> _downloadTemplateDocx() async {
    if (_isDownloadingTemplate) return;
    setState(() => _isDownloadingTemplate = true);

    try {
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Template_Soal_ExamGO';
      final category = _selectedCategory;

      final bytes = DocxTemplateGenerator.generateTemplateBytes(
        title: title,
        category: category,
      );

      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = title
          .replaceAll(RegExp(r'[^\w\s\-]'), '')
          .replaceAll(' ', '_');
      final fileName =
          '${sanitizedTitle.isNotEmpty ? sanitizedTitle : 'Template_Soal_ExamGO'}.docx';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Template "$fileName" siap diunduh.',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
            content: Text(
              'Gagal menyiapkan template: $e',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingTemplate = false);
      }
    }
  }

  // ─── Dialog Edit / Tambah Subtest ─────────────────────────────
  void _showSubtestDialog({ExamSubtest? existing, int? index}) {
    final titleCtrl = TextEditingController(text: existing?.judul ?? '');
    final durCtrl = TextEditingController(
      text: (existing?.durasiMenit ?? 30).toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.splitscreen_rounded,
                color: AppColors.primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                existing != null ? 'Edit Subtest' : 'Tambah Subtest Baru',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nama / Topik Subtest',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Misal: Penalaran Matematika',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Alokasi Waktu (Menit)',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: durCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: '30',
                  suffixText: 'menit',
                  suffixStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: GoogleFonts.poppins(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleCtrl.text.trim();
              final newDur = int.tryParse(durCtrl.text.trim()) ?? 30;
              if (newTitle.isEmpty) return;

              setState(() {
                if (existing != null && index != null) {
                  existing.judul = newTitle;
                  existing.durasiMenit = newDur;
                } else {
                  _subtests.add(
                    ExamSubtest(
                      subtestId: 'ST${_subtests.length + 1}',
                      paketId: '',
                      judul: newTitle,
                      durasiMenit: newDur,
                    ),
                  );
                }
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Simpan',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Pick & Parse File DOCX ───────────────────────────────────
  Future<void> _pickAndParseDocx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        _showErrorDialog(
          'Gagal Membaca Berkas',
          'Aplikasi tidak dapat mengakses data berkas Word yang dipilih. Pastikan berkas tersimpan di penyimpanan lokal dan tidak sedang dibuka oleh aplikasi lain.',
        );
        return;
      }

      setState(() {
        _isLoading = true;
        _pickedFileName = file.name;
        _pickedFileSize = file.size;
        _loadingStatus = 'Mengekstrak struktur dokumen Word & media...';
        _loadingProgress = 0.15;
        _docxResult = null;
      });

      final parseRes = await DocxExamParser.parseDocxBytes(
        bytes: file.bytes!,
        defaultTitle: _titleController.text.trim(),
        defaultCategory: _selectedCategory,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _loadingStatus = status;
              _loadingProgress = progress;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _docxResult = parseRes;
        if (parseRes.isValid && parseRes.package != null) {
          _currentPackage = parseRes.package;
          _titleController.text = _currentPackage!.namaPaket;
          if (_currentPackage!.subtests.isNotEmpty) {
            _subtests = _currentPackage!.subtests;
          }
        }
      });

      if (parseRes.isValid) {
        _showSuccessDialog(
          title: 'Soal Berhasil Divalidasi!',
          message:
              '${parseRes.package?.totalSoal ?? 0} butir soal berhasil diekstrak dan gambar otomatis terhubung ke Google Drive.',
          package: parseRes.package,
        );
      } else {
        _showErrorDialog(
          'Format Soal Belum Sesuai',
          parseRes.errors.join('\n\n'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _docxResult = DocxParseResult(
          isValid: false,
          errors: ['Gagal memproses dokumen: $e'],
        );
      });
      _showErrorDialog(
        'Terjadi Kesalahan Teknis',
        'Dokumen tidak dapat diproses: $e\n\nPastikan berkas berformat Microsoft Word (.docx) standar dan tidak rusak.',
      );
    }
  }

  // ─── Fetch & Parse Google Form ────────────────────────────────
  Future<void> _fetchAndParseGForm() async {
    final url = _gformUrlController.text.trim();
    if (url.isEmpty) {
      _showErrorDialog(
        'Tautan Kosong',
        'Silakan masukkan tautan Google Form publik terlebih dahulu.',
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _loadingStatus = 'Mengakses Google Form & mengekstrak butir soal...';
        _loadingProgress = 0.3;
        _gformResult = null;
      });

      final durasi = int.tryParse(_durationController.text.trim()) ?? 90;
      final parseRes = await GFormExamParser.parseFromUrl(
        formUrl: url,
        defaultCategory: _selectedCategory,
        defaultDurationMinutes: durasi,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _gformResult = parseRes;
        if (parseRes.isValid && parseRes.package != null) {
          _currentPackage = parseRes.package;
          _titleController.text = _currentPackage!.namaPaket;
          if (_currentPackage!.subtests.isNotEmpty) {
            _subtests = _currentPackage!.subtests;
          }
        }
      });

      if (parseRes.isValid) {
        _showSuccessDialog(
          title: 'Google Form Berhasil Dikonversi!',
          message:
              '${parseRes.package?.totalSoal ?? 0} butir soal berhasil diekstrak ke tampilan native ExamGO.',
          package: parseRes.package,
        );
      } else {
        _showErrorDialog(
          'Format Google Form Belum Sesuai',
          parseRes.errors.join('\n\n'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _gformResult = GFormParseResult(
          isValid: false,
          errors: ['Gagal mengakses formulir: $e'],
        );
      });
      _showErrorDialog(
        'Gagal Mengakses Google Form',
        'Terjadi kendala koneksi atau otorisasi: $e\n\nPastikan formulir bersifat publik (dapat dibuka siswa tanpa login akun sekolah khusus).',
      );
    }
  }

  // ─── Navigasi ke Halaman Pratinjau ─────────────────────────────
  void _goToPreview() {
    if (_currentPackage == null || _currentPackage!.totalSoal == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Belum ada soal yang valid untuk dipratinjau.',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    _currentPackage!.namaPaket = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Ujian Baru';
    _currentPackage!.kategori = _selectedCategory;
    _currentPackage!.jenisWaktu = _jenisWaktu;
    _currentPackage!.durasiMenit =
        int.tryParse(_durationController.text.trim()) ?? 90;
    _currentPackage!.allowRetake = false; // Soal buatan guru 1x pengerjaan per device

    if (_subtests.isNotEmpty) {
      final allQuestions = <ExamQuestion>[];
      for (final st in _currentPackage!.subtests) {
        allQuestions.addAll(st.soalList);
      }

      if (_subtests.length == 1) {
        _subtests.first.soalList = allQuestions;
      }
      _currentPackage!.subtests = _subtests;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherExamPreviewScreen(package: _currentPackage!),
      ),
    );
  }

  // ─── Dialog Notifikasi Sukses & Error ─────────────────────────
  void _showSuccessDialog({
    required String title,
    required String message,
    ExamPackage? package,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF334155),
                height: 1.4,
              ),
            ),
            if (package != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricSnippet(
                      'Total Soal',
                      '${package.totalSoal} Soal',
                    ),
                    _buildMetricSnippet(
                      'Subtest',
                      '${package.subtests.length} Babak',
                    ),
                    _buildMetricSnippet('Kategori', package.kategori),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Tutup',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _goToPreview();
            },
            icon: const Icon(
              Icons.visibility_rounded,
              size: 16,
              color: Colors.white,
            ),
            label: Text(
              'Pratinjau Soal',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSnippet(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.45,
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openFormatGuideScreen();
            },
            icon: const Icon(
              Icons.menu_book_rounded,
              size: 16,
              color: AppColors.primaryGreen,
            ),
            label: Text(
              'Panduan Format',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Mengerti',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Buka Halaman Panduan Format Soal DOCX ─────────────────────
  void _openFormatGuideScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DocxFormatGuideScreen(initialCategory: _selectedCategory),
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
              'Buat Paket Ujian',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Mode Pengajar • Buat, Impor & Konversi Soal Otomatis',
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
        leading: const AppBackButton.dark(),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: AppColors.primaryGreen,
                size: 20,
              ),
            ),
            tooltip: 'Panduan Format Soal DOCX',
            onPressed: _openFormatGuideScreen,
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: _buildModernStepperHeader(),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_hasLoadedLicense) _buildTeacherLicenseBanner(),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _buildActiveStepView(),
                    ),
                  ],
                ),
              ),
            ),

            // ─── STICKY BOTTOM NAVIGATION BAR ─────────────────────
            _buildStickyBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherLicenseBanner() {
    if (_isTeacherPremium) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: AppColors.primaryGreen,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Akun Guru Premium: Akses penuh terbitkan paket ujian tanpa batas.',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF065F46),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.card_giftcard_rounded,
            color: Color(0xFF2563EB),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode Percobaan: Sisa $_remainingUploads dari 3 kali kuota buat & terbitkan soal gratis.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E40AF),
              ),
            ),
          ),
          if (_remainingUploads <= 1)
            InkWell(
              onTap: () =>
                  PremiumTokenDialog.show(context, userType: 'TEACHER_PREMIUM'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Upgrade',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Header Stepper Modern & Interaktif ────────────────────────
  Widget _buildModernStepperHeader() {
    return Row(
      children: [
        _buildStepPill(
          stepIndex: 0,
          stepNumber: '1',
          label: 'Informasi',
          isDone: _titleController.text.trim().isNotEmpty,
        ),
        _buildStepSeparator(isDone: _titleController.text.trim().isNotEmpty),
        _buildStepPill(
          stepIndex: 1,
          stepNumber: '2',
          label: 'Subtest (${_subtests.length})',
          isDone: _subtests.isNotEmpty,
        ),
        _buildStepSeparator(isDone: _subtests.isNotEmpty),
        _buildStepPill(
          stepIndex: 2,
          stepNumber: '3',
          label: 'Impor Soal',
          isDone: _currentPackage != null && _currentPackage!.totalSoal > 0,
        ),
      ],
    );
  }

  Widget _buildStepPill({
    required int stepIndex,
    required String stepNumber,
    required String label,
    required bool isDone,
  }) {
    final isCurrent = _currentStep == stepIndex;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentStep = stepIndex);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isCurrent
                ? AppColors.primaryGreen.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent ? AppColors.primaryGreen : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? AppColors.primaryGreen
                      : isCurrent
                      ? AppColors.primaryGreen
                      : const Color(0xFFCBD5E1),
                ),
                child: Center(
                  child: isDone && !isCurrent
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        )
                      : Text(
                          stepNumber,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    color: isCurrent
                        ? const Color(0xFF0F172A)
                        : isDone
                        ? const Color(0xFF334155)
                        : const Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepSeparator({required bool isDone}) {
    return Container(
      width: 16,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: isDone ? AppColors.primaryGreen : const Color(0xFFE2E8F0),
    );
  }

  // ─── Tampilan Sesuai Step Aktif ───────────────────────────────
  Widget _buildActiveStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep1InfoView();
      case 1:
        return _buildStep2SubtestsView();
      case 2:
      default:
        return _buildStep3ImportView();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 1: INFORMASI & KATEGORI UJIAN
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep1InfoView() {
    return Column(
      key: const ValueKey('step_1_info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.edit_note_rounded,
          title: 'Informasi Dasar Paket Ujian',
          subtitle:
              'Masukkan nama paket serta target kategori ujian untuk mengaktifkan preset otomatis.',
        ),
        const SizedBox(height: 16),

        _buildCardContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Judul / Nama Paket Ujian',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Misal: Try Out Akbar SNBT 2026',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                  prefixIcon: const Icon(
                    Icons.school_outlined,
                    size: 20,
                    color: Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Pilih Kategori Ujian',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Memilih kategori akan otomatis menyesuaikan alokasi subtest dan durasi standar.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),
              _buildModernCategoryGrid(),
            ],
          ),
        ),

        const SizedBox(height: 18),

        _buildSectionHeader(
          icon: Icons.timer_outlined,
          title: 'Pengaturan Waktu & Durasi',
          subtitle:
              'Tentukan apakah durasi dihitung global untuk seluruh soal atau terbagi mandiri per subtest.',
        ),
        const SizedBox(height: 16),

        _buildCardContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Model Perhitungan Timer',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTimerModeOption(
                      title: 'Per Subtest',
                      desc: 'Timer berganti tiap sesi',
                      value: 'per_subtest',
                      icon: Icons.splitscreen_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimerModeOption(
                      title: 'Global Paket',
                      desc: '1 Timer untuk semua soal',
                      value: 'per_paket',
                      icon: Icons.hourglass_top_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Total Durasi Ujian (Menit)',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: '90',
                  suffixText: 'menit',
                  suffixStyle: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  prefixIcon: const Icon(
                    Icons.access_time_rounded,
                    size: 20,
                    color: Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModernCategoryGrid() {
    final categories = [
      {
        'id': ExamCategory.snbt,
        'title': 'SNBT UTBK',
        'subtitle': '7 Subtest (TPS & Literasi)',
        'badge': 'Standar PTN',
        'icon': Icons.account_balance_rounded,
      },
      {
        'id': ExamCategory.skd,
        'title': 'SKD Kedinasan',
        'subtitle': '3 Subtest (TWK, TIU, TKP)',
        'badge': 'CPNS / Ikdin',
        'icon': Icons.military_tech_rounded,
      },
      {
        'id': ExamCategory.tkaSma,
        'title': 'TKA SMA',
        'subtitle': 'Wajib & Peminatan Jurusan',
        'badge': 'Tingkat SMA',
        'icon': Icons.school_rounded,
      },
      {
        'id': ExamCategory.tkaSmp,
        'title': 'TKA SMP',
        'subtitle': 'Matematika & B. Indonesia',
        'badge': 'Tingkat SMP',
        'icon': Icons.menu_book_rounded,
      },
      {
        'id': ExamCategory.tkaSd,
        'title': 'TKA SD',
        'subtitle': 'Dasar Akademik Numerasi',
        'badge': 'Tingkat SD',
        'icon': Icons.child_care_rounded,
      },
      {
        'id': ExamCategory.umum,
        'title': 'Ujian Umum',
        'subtitle': 'Ulangan Harian, UTS, & UAS',
        'badge': 'Fleksibel',
        'icon': Icons.assignment_rounded,
      },
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.32,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final isSelected = _selectedCategory == cat['id'];

        return InkWell(
          onTap: () => _applyCategoryPreset(cat['id'] as String),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryGreen
                    : const Color(0xFFE2E8F0),
                width: isSelected ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppColors.primaryGreen.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryGreen.withValues(alpha: 0.15)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        cat['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? AppColors.primaryGreen
                            : const Color(0xFF64748B),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        cat['badge'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF166534)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat['title'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? const Color(0xFF15803D)
                            : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      cat['subtitle'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerModeOption({
    required String title,
    required String desc,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _jenisWaktu == value;

    return InkWell(
      onTap: () => setState(() => _jenisWaktu = value),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen
                : const Color(0xFFE2E8F0),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected
                  ? AppColors.primaryGreen
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF15803D)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 2: STRUKTUR & ALOKASI SUBTEST
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep2SubtestsView() {
    final totalMenit = _subtests.fold<int>(
      0,
      (sum, st) => sum + st.durasiMenit,
    );

    return Column(
      key: const ValueKey('step_2_subtests'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.splitscreen_rounded,
          title: 'Struktur Subtest & Alokasi Menit',
          subtitle:
              'Pengajar dapat menyesuaikan daftar subtest, menambah babak baru, atau mengubah alokasi menit.',
          action: ElevatedButton.icon(
            onPressed: () => _showSubtestDialog(),
            icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            label: Text(
              'Tambah Subtest',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Summary Metric Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.format_list_numbered_rounded,
                        color: Color(0xFF475569),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_subtests.length} Subtest Aktif',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Paket "$_selectedCategory"',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: Color(0xFF166534),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Total: $totalMenit Menit',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (_subtests.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.splitscreen_rounded,
                    size: 36,
                    color: Color(0xFFCBD5E1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Belum ada subtest yang dibuat',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Klik tombol "Tambah Subtest" di atas untuk menambahkan babak ujian.',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._subtests.asMap().entries.map((entry) {
            final idx = entry.key;
            final st = entry.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st.judul,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${st.durasiMenit} Menit',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (st.soalList.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${st.soalList.length} Butir Soal',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF166534),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    tooltip: 'Edit Subtest',
                    onPressed: () =>
                        _showSubtestDialog(existing: st, index: idx),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    tooltip: 'Hapus Subtest',
                    onPressed: () {
                      setState(() => _subtests.removeAt(idx));
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 3: IMPOR & KONVERSI SOAL
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep3ImportView() {
    return Column(
      key: const ValueKey('step_3_import'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.cloud_upload_rounded,
          title: 'Unggah Dokumen Soal Ujian',
          subtitle:
              'Pilih file Word (.docx) atau masukkan link Google Form untuk konversi otomatis ke tampilan ExamGO.',
        ),
        const SizedBox(height: 16),

        _buildCardContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tab Selector
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSourceTab = 0;
                            _sourceTabController.animateTo(0);
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedSourceTab == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedSourceTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_rounded,
                                size: 16,
                                color: _selectedSourceTab == 0
                                    ? AppColors.primaryGreen
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Word (.docx)',
                                  style: GoogleFonts.poppins(
                                    fontWeight: _selectedSourceTab == 0
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12.5,
                                    color: _selectedSourceTab == 0
                                        ? AppColors.primaryGreen
                                        : const Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSourceTab = 1;
                            _sourceTabController.animateTo(1);
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedSourceTab == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedSourceTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 16,
                                color: _selectedSourceTab == 1
                                    ? AppColors.primaryGreen
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '⭐ Google Form',
                                  style: GoogleFonts.poppins(
                                    fontWeight: _selectedSourceTab == 1
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12,
                                    color: _selectedSourceTab == 1
                                        ? AppColors.primaryGreen
                                        : const Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Dynamic Tab View (Tanpa batasan tinggi kaku, bebas overflow)
              _selectedSourceTab == 0
                  ? _buildDocxUploadTab()
                  : _buildGoogleFormTab(),

              // Processing Real-time Progress Card
              if (_isLoading) ...[
                const SizedBox(height: 14),
                _buildProcessingProgressCard(),
              ],

              // Validation Result Banner
              if (_docxResult != null || _gformResult != null) ...[
                const SizedBox(height: 14),
                _buildValidationReportCard(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocxUploadTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _isLoading ? null : _pickAndParseDocx,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 145,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _isLoading
                  ? const Color(0xFFF0FDF4)
                  : _pickedFileName != null
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isLoading || _pickedFileName != null
                    ? AppColors.primaryGreen
                    : const Color(0xFFCBD5E1),
                width: 1.5,
              ),
            ),
            child: _isLoading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sedang Mengunggah & Memvalidasi...',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF15803D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loadingStatus,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF166534),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _pickedFileName != null
                              ? AppColors.primaryGreen.withValues(alpha: 0.15)
                              : const Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _pickedFileName != null
                              ? Icons.task_rounded
                              : Icons.upload_file_rounded,
                          size: 26,
                          color: _pickedFileName != null
                              ? AppColors.primaryGreen
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pickedFileName ??
                            'Ketuk untuk Memilih File Dokumen (.docx)',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _pickedFileName != null
                              ? const Color(0xFF15803D)
                              : const Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pickedFileName != null && _pickedFileSize != null
                            ? '${(_pickedFileSize! / 1024).toStringAsFixed(1)} KB • Klik untuk ganti file'
                            : 'Mendukung gambar, tabel, rumus normal & simbol sains',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: _pickedFileName != null
                              ? const Color(0xFF166534)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isDownloadingTemplate
                    ? null
                    : _downloadTemplateDocx,
                icon: _isDownloadingTemplate
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.download_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                label: Text(
                  'Unduh Template',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFormatGuideScreen,
                icon: const Icon(
                  Icons.menu_book_rounded,
                  size: 16,
                  color: AppColors.primaryGreen,
                ),
                label: Text(
                  'Panduan Lengkap',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryGreen,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoogleFormTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFECFDF5), Color(0xFFF0FDF4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⭐ Rekomendasi: Tempel Link Langsung Jadi CBT',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paling praktis & cepat! Cukup salin tautan Google Form kuis Anda. Soal, gambar, opsi jawaban, dan kisi langsung dikonversi menjadi ujian CBT anti-curang.',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF047857),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(
          'Tautan Google Form:',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _gformUrlController,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: 'https://docs.google.com/forms/d/e/.../viewform',
            hintStyle: GoogleFonts.poppins(
              fontSize: 12.5,
              color: const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            prefixIcon: const Icon(
              Icons.link_rounded,
              size: 20,
              color: Color(0xFF64748B),
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _fetchAndParseGForm,
          icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
          label: Text(
            'Ambil & Konversi Soal Google Form',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Soal dan gambar diekstrak otomatis dari Google Form publik. Kunci jawaban dapat disetel sekaligus menggunakan fitur "⚡ Kunci Cepat" di layar Preview.',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Realtime Processing Progress Card ────────────────────────
  Widget _buildProcessingProgressCard() {
    final percent = (_loadingProgress * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Memproses Dokumen & Media...',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF166534),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percent%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _loadingProgress,
              color: AppColors.primaryGreen,
              backgroundColor: const Color(0xFFDCFCE7),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: Color(0xFF15803D),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _loadingStatus,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF15803D),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Validation Result Report Card ────────────────────────────
  Widget _buildValidationReportCard() {
    final isValid =
        (_docxResult?.isValid ?? false) || (_gformResult?.isValid ?? false);
    final errors = _docxResult?.errors ?? _gformResult?.errors ?? [];
    final warnings = _docxResult?.warnings ?? _gformResult?.warnings ?? [];

    if (isValid) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF86EFAC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Format Valid & Siap Dipratinjau',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF15803D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_currentPackage?.totalSoal ?? 0} butir soal berhasil diekstrak dan siap dipublikasikan.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF166534),
              ),
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEFCE8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFEF08A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: warnings
                      .map(
                        (w) => Text(
                          '• $w',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: const Color(0xFF854D0E),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Format Soal Belum Sesuai',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF991B1B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...errors.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: const Color(0xFF7F1D1D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ─── Sticky Bottom Action Bar ─────────────────────────────────
  Widget _buildStickyBottomBar() {
    final canPreview =
        _currentPackage != null && _currentPackage!.totalSoal > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() => _currentStep -= 1);
                    },
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: Color(0xFF475569),
              ),
              label: Text(
                'Kembali',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () {
                        if (_currentStep < 2) {
                          setState(() => _currentStep += 1);
                        } else {
                          if (canPreview) _goToPreview();
                        }
                      },
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _currentStep == 2
                            ? Icons.visibility_rounded
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _isLoading
                      ? 'Sedang Memproses (${(_loadingProgress * 100).toInt()}%)...'
                      : _currentStep == 0
                      ? 'Lanjut: Atur Subtest (${_subtests.length})'
                      : _currentStep == 1
                      ? 'Lanjut: Unggah & Konversi Soal'
                      : canPreview
                      ? 'Pratinjau Soal (${_currentPackage!.totalSoal} Soal)'
                      : 'Pilih & Validasi Dokumen Soal',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  elevation: (_currentStep < 2 || canPreview) ? 1 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helper Container & Header ────────────────────────────────
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            color: const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
