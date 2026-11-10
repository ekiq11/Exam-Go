import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../constant/app_colors.dart';
import '../../models/exam_question_model.dart';
import '../../utils/math_widget_factory.dart';
import 'tryout_schedule_screen.dart';
import 'widgets/exam_question_table_widget.dart';
import 'widgets/tryout_leaderboard_sheet.dart';
import 'widgets/tryout_spider_chart_widget.dart';

/// Layar pembahasan dan kunci jawaban tryout lengkap dengan rendering LaTeX
class TryoutDiscussionScreen extends StatefulWidget {
  final String title;
  final String kategori;
  final List<ExamQuestion> questions;
  final Map<String, String> studentAnswers;
  final int? score;
  final String? statusKelulusan;
  final bool returnToDashboardOnExit;
  /// Jika true, tombol keluar kembali ke HomeScreen (bukan TryoutScheduleScreen).
  final bool returnToHome;
  final String? token;

  const TryoutDiscussionScreen({
    super.key,
    required this.title,
    required this.kategori,
    required this.questions,
    required this.studentAnswers,
    this.score,
    this.statusKelulusan,
    this.returnToDashboardOnExit = false,
    this.returnToHome = false,
    this.token,
  });

  @override
  State<TryoutDiscussionScreen> createState() => _TryoutDiscussionScreenState();
}

class _TryoutDiscussionScreenState extends State<TryoutDiscussionScreen> {
  String _filter = 'Semua'; // 'Semua', 'Salah', 'Benar', 'Kosong'
  int _currentIndex = 0;
  final ScrollController _chipScrollCtrl = ScrollController();

  List<ExamQuestion> get _filteredQuestions {
    if (_filter == 'Semua') return widget.questions;
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      final correctAns = q.kunci.toUpperCase();
      if (_filter == 'Benar') return userAns.isNotEmpty && userAns == correctAns;
      if (_filter == 'Salah') return userAns.isNotEmpty && userAns != correctAns;
      if (_filter == 'Kosong') return userAns.isEmpty;
      return true;
    }).toList();
  }

  int get _countBenar {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isNotEmpty && userAns == q.kunci.toUpperCase();
    }).length;
  }

  int get _countSalah {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isNotEmpty && userAns != q.kunci.toUpperCase();
    }).length;
  }

  int get _countKosong {
    return widget.questions.where((q) {
      final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
      return userAns.isEmpty;
    }).length;
  }

  @override
  void dispose() {
    _chipScrollCtrl.dispose();
    super.dispose();
  }

  void _onExit() {
    if (widget.returnToHome) {
      // Ujian dari token manual → kembali ke HomeScreen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (widget.returnToDashboardOnExit) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const TryoutScheduleScreen()),
        (route) => route.isFirst,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _scrollToChip(int index) {
    if (!_chipScrollCtrl.hasClients) return;
    final targetOffset = (index * 40.0) - 100.0;
    _chipScrollCtrl.animateTo(
      targetOffset.clamp(0.0, _chipScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showRadarSheet() {
    final subScores = TryoutSubScore.fromQuestions(
      questions: widget.questions,
      studentAnswers: widget.studentAnswers,
      kategori: widget.kategori,
      score: widget.score,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TryoutSpiderChartWidget(
              subScores: subScores,
              title: 'Radar Kemampuan Subtest',
              subtitle: widget.title,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Tutup', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaderboardSheet() {
    final totalSoal = widget.questions.length;
    final effectiveScore = widget.score ?? (totalSoal > 0 ? ((_countBenar / totalSoal) * 100).round() : 0);
    final effectiveToken = (widget.token != null && widget.token!.trim().isNotEmpty)
        ? widget.token!.trim()
        : widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    TryoutLeaderboardSheet.show(
      context,
      token: effectiveToken,
      title: widget.title,
      kategori: widget.kategori,
      userScore: effectiveScore,
    );
  }

  void _showShareModal() {
    final totalSoal = widget.questions.length;
    final effectiveScore = widget.score ?? (totalSoal > 0 ? ((_countBenar / totalSoal) * 100).round() : 0);
    final accuracy = totalSoal > 0 ? ((_countBenar / totalSoal) * 100).toStringAsFixed(1) : '0';
    final statusText = (widget.statusKelulusan != null && widget.statusKelulusan!.isNotEmpty)
        ? widget.statusKelulusan!
        : (effectiveScore >= 65 ? 'Lulus Passing Grade' : 'Belum Memenuhi');

    final shareText = '🎓 *HASIL RESMI TRYOUT EXAMGO*\n'
        '━━━━━━━━━━━━━━━━━━━━━━\n'
        '📝 *Ujian:* ${widget.title}\n'
        '🏷️ *Kategori:* ${widget.kategori.toUpperCase()}\n'
        '🏆 *Skor Akhir:* *$effectiveScore*\n'
        '🎯 *Akurasi:* *$accuracy%*\n'
        '📊 *Evaluasi:* *$statusText*\n'
        '✅ Benar: $_countBenar | ❌ Salah: $_countSalah | ⏳ Kosong: $_countKosong\n'
        '━━━━━━━━━━━━━━━━━━━━━━\n'
        '📲 Dikerjakan di aplikasi *ExamGO* — Simulasi CAT BKN & UTBK-SNBT Terlengkap!\n'
        'Tersedia di Google Play Store & Apple App Store.';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.share_rounded, color: AppColors.primaryGreen, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bagikan Hasil Tryout',
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Pamerkan pencapaian skor ke teman & media sosial',
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.kategori.toUpperCase(),
                          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      Text(
                        statusText.toUpperCase(),
                        style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFFDE047)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SKOR AKHIR', style: GoogleFonts.poppins(fontSize: 9, color: Colors.white70)),
                          Text('$effectiveScore', style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text('Akurasi', style: GoogleFonts.poppins(fontSize: 9, color: Colors.white70)),
                            Text('$accuracy%', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareText));
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Teks hasil tryout disalin ke clipboard!', style: GoogleFonts.poppins(fontSize: 12)),
                          backgroundColor: const Color(0xFF0F172A),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: Text('Salin Teks', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      SharePlus.instance.share(ShareParams(text: shareText));
                    },
                    icon: const Icon(Icons.share_rounded, size: 16, color: Colors.white),
                    label: Text('Bagikan', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredQuestions;
    if (_currentIndex >= filtered.length && filtered.isNotEmpty) {
      _currentIndex = 0;
    }

    final currentQ = filtered.isNotEmpty ? filtered[_currentIndex] : null;

    return PopScope(
      canPop: !widget.returnToDashboardOnExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: widget.returnToDashboardOnExit ? 'Kembali ke Dashboard Tryout' : 'Kembali',
            onPressed: _onExit,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Pembahasan & Kunci',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.title,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          backgroundColor: AppColors.primaryGreen,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFDE047)),
              tooltip: 'Peringkat Nasional & Target Kampus',
              onPressed: _showLeaderboardSheet,
            ),
            IconButton(
              icon: const Icon(Icons.radar_rounded, color: Colors.white),
              tooltip: 'Grafik Radar Kemampuan',
              onPressed: _showRadarSheet,
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              tooltip: 'Bagikan Hasil Tryout',
              onPressed: _showShareModal,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // Card Skor Modern & Profesional
            _buildScoreCard(),

            // Filter Chips
            _buildFilterChips(),

            // Nomor Soal Indicator Horizontal Strip
            if (filtered.isNotEmpty) _buildNumberSelector(filtered),

            // Main Question Card & Options & Pembahasan
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyFilteredState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: _buildQuestionDetailCard(currentQ!, _currentIndex + 1, filtered.length),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: filtered.isEmpty ? null : _buildStickyBottomNav(filtered.length),
      ),
    );
  }

  Widget _buildScoreCard() {
    final totalSoal = widget.questions.length;
    final effectiveScore = widget.score ?? (totalSoal > 0 ? ((_countBenar / totalSoal) * 100).round() : 0);
    final accuracy = totalSoal > 0 ? ((_countBenar / totalSoal) * 100).toStringAsFixed(1) : '0';
    final isLulus = widget.statusKelulusan != null && widget.statusKelulusan!.toLowerCase().contains('lulus');
    final statusText = (widget.statusKelulusan != null && widget.statusKelulusan!.isNotEmpty)
        ? widget.statusKelulusan!
        : (effectiveScore >= 65 ? 'Lulus Passing Grade' : 'Belum Memenuhi');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B5E20),
            Color(0xFF2E7D32),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.22),
            offset: const Offset(0, 5),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        children: [
          // Baris Atas: Kategori Badge & Status Pill
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_rounded, size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'TRYOUT ${widget.kategori.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: (isLulus || effectiveScore >= 65)
                        ? const Color(0xFF4ADE80).withValues(alpha: 0.22)
                        : const Color(0xFFFBBF24).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (isLulus || effectiveScore >= 65)
                          ? const Color(0xFF4ADE80).withValues(alpha: 0.5)
                          : const Color(0xFFFBBF24).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    statusText.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: (isLulus || effectiveScore >= 65)
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFDE68A),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Baris Tengah: Hero Score & Akurasi
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'SKOR HASIL',
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                        letterSpacing: 0.8,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$effectiveScore',
                          style: GoogleFonts.poppins(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'PTS',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF86EFAC),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                InkWell(
                  onTap: _showLeaderboardSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Peringkat',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.emoji_events_rounded, size: 13, color: Color(0xFFFDE047)),
                            const SizedBox(width: 3),
                            Text(
                              'Rank',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _showRadarSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Radar',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.radar_rounded, size: 13, color: Color(0xFFFDE047)),
                            const SizedBox(width: 3),
                            Text(
                              'Lihat',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _showShareModal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Share',
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.share_rounded, size: 12, color: Color(0xFF67E8F9)),
                            const SizedBox(width: 2.5),
                            Text(
                              'Hasil',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Akurasi',
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 13, color: Color(0xFFFDE047)),
                          const SizedBox(width: 2),
                          Text(
                            '$accuracy%',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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

          const SizedBox(height: 10),

          // Baris Bawah: 4 Mini Stat Pills (Total, Benar, Salah, Kosong)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildMiniStatBox('Total', '$totalSoal', Icons.format_list_numbered_rounded, const Color(0xFF475569), const Color(0xFFF8FAFC)),
                const SizedBox(width: 5),
                _buildMiniStatBox('Benar', '$_countBenar', Icons.check_circle_rounded, const Color(0xFF15803D), const Color(0xFFDCFCE7)),
                const SizedBox(width: 5),
                _buildMiniStatBox('Salah', '$_countSalah', Icons.cancel_rounded, const Color(0xFFB91C1C), const Color(0xFFFEE2E2)),
                const SizedBox(width: 5),
                _buildMiniStatBox('Kosong', '$_countKosong', Icons.remove_circle_outline_rounded, const Color(0xFF64748B), const Color(0xFFF1F5F9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatBox(String label, String value, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 11, color: color),
                  const SizedBox(width: 2.5),
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottomNav(int totalFiltered) {
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < totalFiltered - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Tombol Sebelumnya
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: hasPrev
                      ? () {
                          setState(() => _currentIndex--);
                          _scrollToChip(_currentIndex);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(
                    'Sebelumnya',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    side: BorderSide(
                      color: hasPrev ? AppColors.primaryGreen : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Tombol Berikutnya
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: hasNext
                      ? () {
                          setState(() => _currentIndex++);
                          _scrollToChip(_currentIndex);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    'Berikutnya',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Semua', 'Salah', 'Benar', 'Kosong'];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final f = filters[idx];
          final isSelected = _filter == f;
          return ChoiceChip(
            label: Text(
              f,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            selected: isSelected,
            selectedColor: AppColors.primaryGreen,
            backgroundColor: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onSelected: (_) {
              setState(() {
                _filter = f;
                _currentIndex = 0;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildNumberSelector(List<ExamQuestion> list) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView.separated(
        controller: _chipScrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final q = list[i];
          final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
          final isCorrect = userAns.isNotEmpty && userAns == q.kunci.toUpperCase();
          final isWrong = userAns.isNotEmpty && userAns != q.kunci.toUpperCase();
          final isSelected = i == _currentIndex;

          Color bg;
          Color textCol;
          if (isCorrect) {
            bg = const Color(0xFFDCFCE7);
            textCol = const Color(0xFF15803D);
          } else if (isWrong) {
            bg = const Color(0xFFFEE2E2);
            textCol = const Color(0xFFB91C1C);
          } else {
            bg = const Color(0xFFF1F5F9);
            textCol = const Color(0xFF64748B);
          }

          return GestureDetector(
            onTap: () => setState(() => _currentIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.primaryGreen : Colors.transparent,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Text(
                '${q.nomorSoal}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textCol,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuestionDetailCard(ExamQuestion q, int displayNum, int totalFiltered) {
    final userAns = widget.studentAnswers[q.soalId]?.toUpperCase() ?? '';
    final correctAns = q.kunci.toUpperCase();
    final isCorrect = userAns.isNotEmpty && userAns == correctAns;
    final isWrong = userAns.isNotEmpty && userAns != correctAns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Soal
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Soal No. ${q.nomorSoal}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? const Color(0xFFDCFCE7)
                          : (isWrong ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCorrect
                              ? Icons.check_circle_rounded
                              : (isWrong ? Icons.cancel_rounded : Icons.help_outline_rounded),
                          size: 14,
                          color: isCorrect
                              ? const Color(0xFF16A34A)
                              : (isWrong ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          userAns.isEmpty
                              ? 'Tidak Dijawab'
                              : (isCorrect ? 'Jawaban Benar ($userAns)' : 'Jawaban Salah ($userAns)'),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCorrect
                                ? const Color(0xFF15803D)
                                : (isWrong ? const Color(0xFFB91C1C) : const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Stimulus Teks Bacaan jika ada (di atas pertanyaan)
              if (q.tabel.isNotEmpty &&
                  ExamQuestionTableWidget.isReadingPassage(
                    q.tabel,
                    subtestJudul: widget.title,
                  )) ...[
                ExamQuestionTableWidget(
                  tabelStr: q.tabel,
                  subtestJudul: widget.title,
                ),
                const Divider(height: 20, thickness: 1, color: Color(0xFFF1F5F9)),
              ],

              // Pertanyaan Teks
              HtmlWidget(
                MathHtmlFormatter.format(q.pertanyaan),
                factoryBuilder: () => MathWidgetFactory(fontSize: 14),
                textStyle: GoogleFonts.poppins(fontSize: 13.5, color: const Color(0xFF0F172A), height: 1.5),
              ),

              // Tabel Data Numerik jika ada (di bawah pertanyaan)
              if (q.tabel.isNotEmpty &&
                  !ExamQuestionTableWidget.isReadingPassage(
                    q.tabel,
                    subtestJudul: widget.title,
                  )) ...[
                const SizedBox(height: 12),
                ExamQuestionTableWidget(
                  tabelStr: q.tabel,
                  subtestJudul: widget.title,
                ),
              ],

              if (q.gambar.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    MathHtmlFormatter.convertDriveUrl(q.gambar),
                    headers: MathHtmlFormatter.networkImageHeaders,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Pilihan Jawaban A, B, C, D, E
        Text(
          'Pilihan Jawaban:',
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
        ),
        const SizedBox(height: 8),

        ...['A', 'B', 'C', 'D', 'E'].map((opt) {
          final text = _getOptionText(q, opt);
          if (text.isEmpty && opt != 'A' && opt != 'B' && opt != 'C' && opt != 'D') {
            return const SizedBox.shrink();
          }

          final isKey = opt == correctAns;
          final isChosen = opt == userAns;

          Color borderColor;
          Color bgColor;
          if (isKey) {
            borderColor = const Color(0xFF16A34A);
            bgColor = const Color(0xFFF0FDF4);
          } else if (isChosen && !isKey) {
            borderColor = const Color(0xFFDC2626);
            bgColor = const Color(0xFFFEF2F2);
          } else {
            borderColor = const Color(0xFFE2E8F0);
            bgColor = Colors.white;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: (isKey || isChosen) ? 1.5 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isKey
                        ? const Color(0xFF16A34A)
                        : (isChosen ? const Color(0xFFDC2626) : const Color(0xFFF1F5F9)),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    opt,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (isKey || isChosen) ? Colors.white : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HtmlWidget(
                    MathHtmlFormatter.format(text),
                    factoryBuilder: () => MathWidgetFactory(fontSize: 13),
                    textStyle: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1E293B)),
                  ),
                ),
                if (isKey)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'KUNCI',
                      style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFF15803D)),
                    ),
                  ),
                if (isChosen && !isKey)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PILIHANMU',
                      style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFFB91C1C)),
                    ),
                  ),
              ],
            ),
          );
        }),

        const SizedBox(height: 14),

        // Kotak Pembahasan Lengkap
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_rounded, color: Color(0xFF15803D), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Pembahasan Soal',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF166534),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Kunci: $correctAns',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (q.pembahasan.isNotEmpty)
                HtmlWidget(
                  MathHtmlFormatter.format(q.pembahasan),
                  factoryBuilder: () => MathWidgetFactory(fontSize: 13),
                  textStyle: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF14532D), height: 1.5),
                )
              else
                Text(
                  'Kunci jawaban yang benar adalah opsi $correctAns. Pembahasan teks belum disediakan untuk butir ini.',
                  style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF15803D), fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getOptionText(ExamQuestion q, String opt) {
    switch (opt) {
      case 'A': return q.opsiA;
      case 'B': return q.opsiB;
      case 'C': return q.opsiC;
      case 'D': return q.opsiD;
      case 'E': return q.opsiE;
      default: return '';
    }
  }

  Widget _buildEmptyFilteredState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.filter_list_off_rounded, size: 40, color: Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          Text(
            'Tidak ada butir soal dengan status "$_filter"',
            style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}
