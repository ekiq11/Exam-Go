import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constant/app_colors.dart';
import '../../models/exam_question_model.dart';
import '../../services/license_service.dart';
import '../../services/monitoring_service.dart';
import '../../services/qr_payload.dart';
import '../../utils/math_widget_factory.dart';
import '../widgets/premium_token_dialog.dart';
import 'teacher_exam_published_dialog.dart';

class TeacherExamPreviewScreen extends StatefulWidget {
  final ExamPackage package;

  const TeacherExamPreviewScreen({super.key, required this.package});

  @override
  State<TeacherExamPreviewScreen> createState() => _TeacherExamPreviewScreenState();
}

class _TeacherExamPreviewScreenState extends State<TeacherExamPreviewScreen> {
  bool _isPublishing = false;
  String _publishProgress = '';
  double _publishProgressPercent = 0.0;
  String? _lastTokenUsed;

  String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  void _showQuickKeyDialog(ExamSubtest st) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tempel Kunci Cepat',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan urutan kunci jawaban untuk ${st.soalList.length} butir soal (${st.judul}).\n\n'
              'Format bebas, contoh:\n'
              '• Huruf polos: ABCDEBACDE...\n'
              '• Berurutan: 1. A, 2. B, 3. C, 4. D...',
              style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Tempel kunci di sini (misal: ABCDEBACDE...)',
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.toUpperCase();
              final matches = RegExp(r'[A-E]').allMatches(raw).map((m) => m.group(0)!).toList();
              if (matches.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tidak ditemukan huruf kunci A-E yang valid.')),
                );
                return;
              }
              int applied = 0;
              for (int i = 0; i < st.soalList.length && i < matches.length; i++) {
                st.soalList[i].kunci = matches[i];
                applied++;
              }
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.primaryGreen,
                  content: Text('Berhasil mengisi $applied kunci jawaban untuk ${st.judul}!'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Terapkan Kunci', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _promptPublishDialog() {
    final defaultToken = _generateToken();
    final tokenCtrl = TextEditingController(text: defaultToken);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.key_rounded, color: AppColors.primaryGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Terbitkan Paket Soal',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tentukan Token Ujian untuk siswa. Anda bisa memakai token acak atau mengetik token kustom sendiri (contoh: TONAS2026):',
              style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tokenCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                // Uppercase only — teacher tokens can be freeform (TONAS2026, etc.)
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                TextInputFormatter.withFunction((old, val) => val.copyWith(
                  text: val.text.toUpperCase(),
                  selection: val.selection,
                )),
              ],
              decoration: InputDecoration(
                labelText: 'Token / Kode Ujian',
                hintText: 'Contoh: TONAS2026',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: Color(0xFF64748B)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final chosen = tokenCtrl.text.trim().toUpperCase().replaceAll(' ', '');
              if (chosen.isEmpty) return;
              Navigator.pop(ctx);
              _publishExam(chosen);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text('Terbitkan Sekarang', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _publishExam([String? customToken]) async {
    final isPremium = await LicenseService.instance.isTeacherPremium();
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    if (!isPremium && list.length >= 5) {
      if (!mounted) return;
      _showTokenLimitDialog();
      return;
    }

    final token = customToken?.trim().toUpperCase().replaceAll(' ', '') ?? _lastTokenUsed ?? _generateToken();
    _lastTokenUsed = token;

    setState(() {
      _isPublishing = true;
      _publishProgress = 'Menyiapkan token [$token] & sesi ujian...';
      _publishProgressPercent = 0.05;
    });

    try {
      final examUrl = 'EXAMGO_TRYOUT://$token';
      final firestore = FirebaseFirestore.instance;

      setState(() {
        _publishProgress = 'Menyimpan paket ujian ke Firestore...';
        _publishProgressPercent = 0.15;
      });

      // 1. Simpan paket_tryout
      await firestore.collection('paket_tryout').doc(token).set({
        'paket_id': token,
        'nama_paket': widget.package.namaPaket,
        'kategori': widget.package.kategori,
        'jenis_waktu': widget.package.jenisWaktu,
        'durasi_menit': widget.package.durasiMenit,
        'total_soal': widget.package.totalSoal,
        'created_at': FieldValue.serverTimestamp(),
        'status': 'ACTIVE',
      });

      // 2. Simpan subtest & soal
      int totalSaved = 0;
      final totalSoal = widget.package.totalSoal;

      for (int stIdx = 0; stIdx < widget.package.subtests.length; stIdx++) {
        final st = widget.package.subtests[stIdx];
        final subtestDocId = '${token}_ST${stIdx + 1}';

        await firestore.collection('subtest').doc(subtestDocId).set({
          'subtest_id': subtestDocId,
          'paket_id': token,
          'judul_subtest': st.judul,
          'durasi_menit': st.durasiMenit,
          'soal_count': st.soalList.length,
        });

        for (int qIdx = 0; qIdx < st.soalList.length; qIdx++) {
          final q = st.soalList[qIdx];
          final soalDocId = '${subtestDocId}_Q${qIdx + 1}';

          await firestore.collection('tryout_soal').doc(soalDocId).set({
            'soal_id': soalDocId,
            'subtest_id': subtestDocId,
            'paket_id': token,
            'nomor_soal': q.nomorSoal,
            'pertanyaan': q.pertanyaan,
            'opsi_a': q.opsiA,
            'opsi_b': q.opsiB,
            'opsi_c': q.opsiC,
            'opsi_d': q.opsiD,
            'opsi_e': q.opsiE,
            'gam_a': q.gamA,
            'gam_b': q.gamB,
            'gam_c': q.gamC,
            'gam_d': q.gamD,
            'gam_e': q.gamE,
            'kunci': q.kunci.toUpperCase(),
            'pembahasan': q.pembahasan,
            'gambar': q.gambar,
          });

          totalSaved++;
          final percent = 0.15 + (0.70 * (totalSaved / (totalSoal > 0 ? totalSoal : 1)));
          setState(() {
            _publishProgress = 'Menyimpan butir soal ($totalSaved/$totalSoal)...';
            _publishProgressPercent = percent.clamp(0.0, 0.88);
          });
        }
      }

      // 3. Buat sesi monitoring di exam_sessions/{token}
      setState(() {
        _publishProgress = 'Mendaftarkan sesi monitoring anti-curang...';
        _publishProgressPercent = 0.92;
      });
      await MonitoringService.instance.createExamSession(
        examId: token,
        title: widget.package.namaPaket,
        url: examUrl,
      );

      // 4. Generate signed QR Payload
      final qrSigned = QRPayloadService.generate(examUrl, title: widget.package.namaPaket);

      // 5. Simpan di riwayat guru lokal agar muncul di Monitoring List
      final entry = '$token|${widget.package.namaPaket}|${DateTime.now().millisecondsSinceEpoch}|$examUrl|$qrSigned';
      list.insert(0, entry);
      if (!isPremium && list.length > 5) {
        list.removeLast();
      } else if (list.length > 50) {
        list.removeLast();
      }
      await prefs.setStringList('teacher_exam_history', list);

      if (!mounted) return;

      setState(() {
        _publishProgress = 'Selesai!';
        _publishProgressPercent = 1.0;
        _isPublishing = false;
      });

      // Tampilkan popup QR & Token
      TeacherExamPublishedDialog.show(
        context,
        examTitle: widget.package.namaPaket,
        token: token,
        qrPayload: qrSigned,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      _showPublishErrorDialog(e.toString());
    }
  }

  void _showTokenLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Batas 5 Token Ujian Aktif',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          'Akun Guru Standar dibatasi maksimal memiliki 5 token ujian aktif guna efisiensi cloud.\n\nBeralih ke Guru Premium untuk menerbitkan ujian tanpa batas dan membuka fitur analitik lengkap.',
          style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF475569), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              PremiumTokenDialog.show(
                context,
                userType: 'TEACHER_PREMIUM',
              );
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Aktivasi Kode', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              LicenseService.instance.openLynkIdPage(userType: 'TEACHER_PREMIUM');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Upgrade 👑', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPublishErrorDialog(String error) {
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
              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Gagal Menerbitkan Ujian',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terjadi kendala saat menyimpan paket ujian ke Firestore:\n\n$error',
              style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'Pastikan koneksi internet stabil lalu tekan "Coba Terbitkan Lagi".',
              style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _publishExam();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
            label: Text('Coba Terbitkan Lagi', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.package;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF7),
      appBar: AppBar(
        title: Text(
          'Preview Soal Ujian',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: _isPublishing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_rounded, color: AppColors.primaryGreen, size: 36),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Menerbitkan Paket Ujian...',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _publishProgress,
                        style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _publishProgressPercent,
                          color: AppColors.primaryGreen,
                          backgroundColor: const Color(0xFFDCFCE7),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Status Upload Server',
                            style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF94A3B8)),
                          ),
                          Text(
                            '${(_publishProgressPercent * 100).toInt()}%',
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_clock_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Harap tidak menutup aplikasi sampai QR Code & Token ujian tampil.',
                                style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                // Header Info Bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pkg.namaPaket,
                              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${pkg.kategori} • ${pkg.subtests.length} Subtest • ${pkg.totalSoal} Soal • ${pkg.durasiMenit} Menit',
                              style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          pkg.jenisWaktu == 'per_subtest' ? 'Per Subtest' : 'Per Paket',
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                        ),
                      ),
                    ],
                  ),
                ),

                // Question List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: pkg.subtests.length,
                    itemBuilder: (context, stIdx) {
                      final st = pkg.subtests[stIdx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subtest Header
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B5E20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bookmarks_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${st.judul} (${st.durasiMenit} Menit • ${st.soalList.length} Soal)',
                                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _showQuickKeyDialog(st),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flash_on_rounded, size: 14, color: Colors.amberAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Kunci Cepat',
                                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Questions in this subtest
                          ...st.soalList.map((q) => _buildQuestionCard(q)),
                        ],
                      );
                    },
                  ),
                ),

                // Bottom Action Bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isPublishing ? null : _promptPublishDialog,
                      icon: const Icon(Icons.publish_rounded, color: Colors.white),
                      label: Text(
                        'Publish Ujian & Buat QR Code/Token',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuestionCard(ExamQuestion q) {
    final driveImg = MathHtmlFormatter.convertDriveUrl(q.gambar);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Nomor & Ubah Kunci
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No. ${q.nomorSoal}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  Text('Kunci: ', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primaryGreen),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: q.kunci,
                        isDense: true,
                        items: ['A', 'B', 'C', 'D', 'E'].map((k) {
                          return DropdownMenuItem(
                            value: k,
                            child: Text(k, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                          );
                        }).toList(),
                        onChanged: (newKey) {
                          if (newKey != null) {
                            setState(() => q.kunci = newKey);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Teks Pertanyaan (dengan LaTeX Renderer)
          HtmlWidget(
            MathHtmlFormatter.format(q.pertanyaan),
            textStyle: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF212121), height: 1.5),
            factoryBuilder: () => MathWidgetFactory(fontSize: 13.5),
          ),

          // Tabel Soal jika ada
          if (q.tabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildQuestionTable(q.tabel),
          ],

          // Gambar Pertanyaan jika ada
          if (driveImg.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: driveImg,
                placeholder: (context, url) => Container(
                  height: 120,
                  color: Colors.grey.shade100,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen)),
                ),
                errorWidget: (context, url, error) => Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.broken_image_outlined, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gambar tidak dapat dimuat ($driveImg)',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Opsi Jawaban A s.d. E
          _buildOptionTile('A', q.opsiA, q.gamA, q.kunci == 'A'),
          _buildOptionTile('B', q.opsiB, q.gamB, q.kunci == 'B'),
          _buildOptionTile('C', q.opsiC, q.gamC, q.kunci == 'C'),
          _buildOptionTile('D', q.opsiD, q.gamD, q.kunci == 'D'),
          if (q.opsiE.isNotEmpty || q.gamE.isNotEmpty)
            _buildOptionTile('E', q.opsiE, q.gamE, q.kunci == 'E'),

          // Pembahasan jika ada
          if (q.pembahasan.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 Pembahasan:', style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                  const SizedBox(height: 4),
                  HtmlWidget(
                    MathHtmlFormatter.format(q.pembahasan),
                    textStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.brown.shade900),
                    factoryBuilder: () => MathWidgetFactory(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile(String key, String text, String img, bool isCorrect) {
    if (text.isEmpty && img.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCorrect ? const Color(0xFFE8F5E9) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCorrect ? AppColors.primaryGreen : Colors.grey.shade300,
          width: isCorrect ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCorrect ? AppColors.primaryGreen : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                key,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isCorrect ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (text.isNotEmpty)
                  HtmlWidget(
                    MathHtmlFormatter.format(text),
                    textStyle: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
                      color: isCorrect ? const Color(0xFF1B5E20) : Colors.black87,
                    ),
                    factoryBuilder: () => MathWidgetFactory(fontSize: 12.5),
                  ),
                if (img.isNotEmpty) ...[
                  if (text.isNotEmpty) const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      MathHtmlFormatter.convertDriveUrl(img),
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCorrect)
            const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 18),
        ],
      ),
    );
  }

  Widget _buildQuestionTable(String tabelStr) {
    if (tabelStr.isEmpty) return const SizedBox.shrink();
    try {
      final rowsArr = tabelStr.contains('===')
          ? tabelStr.split('===')
          : tabelStr.split(',/');
      final delim = tabelStr.contains('===') ? '|||' : '-';
      final tableRows = <TableRow>[];

      for (int k = 0; k < rowsArr.length; k++) {
        final parts = rowsArr[k].split(delim);
        if (parts.isNotEmpty) parts.removeAt(0);
        if (parts.isEmpty) continue;
        final isHeader = k == 0;

        tableRows.add(TableRow(
          decoration: BoxDecoration(
            color: isHeader
                ? const Color(0xFFF5F5F5)
                : (k.isEven ? const Color(0xFFFAFAFA) : Colors.white),
          ),
          children: parts.map((cell) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: HtmlWidget(
                MathHtmlFormatter.format(cell.trim()),
                textStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  color: const Color(0xFF212121),
                ),
                factoryBuilder: () => MathWidgetFactory(fontSize: 12),
              ),
            );
          }).toList(),
        ));
      }

      if (tableRows.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade200, width: 1),
          children: tableRows,
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

