import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/services/tryout_schedule_service.dart';
import 'package:examgo/utils/indo_date_formatter.dart';
import 'package:examgo/view/student/event_dashboard_screen.dart';
import 'package:examgo/view/student/tryout_discussion_screen.dart';
import 'package:examgo/view/student/student_exam_session_screen.dart';
import 'package:examgo/view/pre_exam_checklist.dart';
import 'package:examgo/view/widgets/premium_token_dialog.dart';
import 'package:examgo/view/student/widgets/tryout_card_widget.dart';
import 'package:examgo/view/student/widgets/tryout_detail_sheet.dart';

/// Halaman Katalog Paket & Jadwal Tryout Nasional serta Riwayat & Pembahasan
class TryoutScheduleScreen extends StatefulWidget {
  const TryoutScheduleScreen({super.key});

  @override
  State<TryoutScheduleScreen> createState() => _TryoutScheduleScreenState();
}

class _TryoutScheduleScreenState extends State<TryoutScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<TryoutSchedule> _allSchedules = [];
  List<StudentTryoutHistoryItem> _historyList = [];
  String _selectedCategory = 'Semua';

  final List<String> _categories = [
    'Semua',
    'EVENT',
    'SNBT',
    'SKD',
    'TKA SMA',
    'TKA SMP',
    'TKA SD',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_tabController.index == 1) _loadHistory();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadSchedules(), _loadHistory()]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSchedules() async {
    final list = await TryoutScheduleService.instance.getActiveSchedules();
    if (mounted) {
      setState(() {
        _allSchedules = list;
      });
    }
  }

  Future<void> _loadHistory() async {
    final list = await StudentTryoutHistoryService.instance.getHistory();
    if (mounted) {
      setState(() {
        _historyList = list;
      });
    }
  }

  List<TryoutSchedule> get _filteredSchedules {
    if (_selectedCategory == 'Semua') return _allSchedules;
    return _allSchedules.where((s) {
      final category = _selectedCategory.toUpperCase();
      return s.jenisTest.contains(category) ||
          s.namaPaket.toUpperCase().contains(category);
    }).toList();
  }

  void _showEventTokenDialog() {
    final tokenCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.confirmation_number_rounded,
                color: Color(0xFFD97706),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Masuk Tiket Event',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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
              'Masukkan kode token event dari email Lynk.id atau panitia sekolah untuk langsung masuk ke Dashboard Event.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tokenCtrl,
              textCapitalization: TextCapitalization.characters,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              decoration: InputDecoration(
                hintText: 'Misal: EVENT-ABCD-1234',
                hintStyle: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primaryGreen,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final raw = tokenCtrl.text.trim().toUpperCase();
              if (raw.isEmpty) return;
              Navigator.pop(ctx);

              final res = await LicenseService.instance.activateToken(
                rawToken: raw,
                expectedType: 'STUDENT_LIFETIME',
              );

              if (!mounted) return;
              final target = res.targetExamId ?? raw;
              if (res.isSuccess ||
                  res.message.contains('aktif kembali') ||
                  raw.startsWith('EVENT')) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        EventDashboardScreen(eventId: target, eventToken: raw),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res.message),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Buka Event',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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
              'Paket Tryout & Riwayat',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16.5,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              'Simulasi Ujian & Pembahasan Mandiri',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.confirmation_number_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
            tooltip: 'Masuk dengan Token Event',
            onPressed: _showEventTokenDialog,
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            tooltip: 'Segarkan Data',
            onPressed: _loadData,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              labelColor: AppColors.primaryGreen,
              unselectedLabelColor: Colors.white,
              tabs: const [
                Tab(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.layers_rounded, size: 16),
                      SizedBox(width: 7),
                      Text('Daftar Tryout'),
                    ],
                  ),
                ),
                Tab(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_edu_rounded, size: 16),
                      SizedBox(width: 7),
                      Text('Riwayat & Nilai'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Katalog Tryout
          _buildTryoutCatalogTab(),

          // Tab 2: Riwayat & Pembahasan Siswa
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildTryoutCatalogTab() {
    return Column(
      children: [
        // Header Banner Premium
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFBBF24),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Akses Eksklusif Siswa Premium',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Tryout dapat dikerjakan berulang kali & memiliki pembahasan lengkap.',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Category Pills Filter
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = cat == _selectedCategory;
              return ChoiceChip(
                label: Text(
                  cat,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.primaryGreen,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primaryGreen
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                onSelected: (_) => setState(() => _selectedCategory = cat),
              );
            },
          ),
        ),

        // Main List
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primaryGreen,
                  onRefresh: _loadData,
                  child: _filteredSchedules.isEmpty
                      ? _buildEmptyCatalogState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: _filteredSchedules.length,
                          itemBuilder: (context, index) {
                            final item = _filteredSchedules[index];
                            return TryoutCardWidget(
                              schedule: item,
                              onTap: () async {
                                if (item.jenisTest == 'EVENT') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EventDashboardScreen(
                                        eventId: item.paketId,
                                        initialSchedule: item,
                                      ),
                                    ),
                                  );
                                } else {
                                  final shouldStart =
                                      await TryoutDetailSheet.show(
                                        context,
                                        item,
                                      );
                                  if (shouldStart == true && context.mounted) {
                                    _startTryout(item);
                                  }
                                }
                              },
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Future<void> _startTryout(TryoutSchedule schedule) async {
    // 1. Cek kuota ujian siswa
    final canTake = await LicenseService.instance.canStudentTakeExam();
    if (!canTake) {
      if (mounted) {
        PremiumTokenDialog.show(context, userType: 'STUDENT_LIFETIME');
      }
      return;
    }

    if (!mounted) return;

    // 2. Tampilkan Pre-Exam Checklist (Cek baterai, identitas siswa, aturan)
    final identity = await PreExamChecklistDialog.show(
      context,
      schedule.namaPaket,
    );
    if (identity == null || !mounted) return;

    final name = identity['name'] ?? 'Siswa';
    final nis = identity['nis'] ?? '-';

    // 3. Catat pemakaian 1 kuota ujian
    await LicenseService.instance.recordExamAttempt();

    if (!mounted) return;

    // 4. Masuk ke Sesi Ujian Siswa
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentExamSessionScreen(
          token: schedule.paketId,
          studentName: name,
          studentNis: nis,
          initialSchedule: schedule,
        ),
      ),
    );

    if (mounted) _loadData();
  }

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_historyList.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: const Icon(
                        Icons.history_edu_rounded,
                        size: 32,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum Ada Riwayat Ujian',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kerjakan paket tryout di tab Daftar Tryout.\nAnalisis skor dan pembahasan lengkap akan tersimpan otomatis di sini.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => _tabController.animateTo(0),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                      label: Text(
                        'Mulai Kerjakan Tryout',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
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

    // Hitung KPI Ringkasan
    final totalUjian = _historyList.length;
    final totalScore = _historyList.fold<int>(
      0,
      (sum, item) => sum + item.finalScore,
    );
    final avgScore = (totalScore / totalUjian).round();
    final highestScore = _historyList
        .map((e) => e.finalScore)
        .reduce((a, b) => a > b ? a : b);
    final totalLulus = _historyList.where((e) => e.isPassed).length;

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: _historyList.length + 1, // +1 untuk header stats
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHistoryHeaderStats(
              totalUjian: totalUjian,
              avgScore: avgScore,
              highestScore: highestScore,
              totalLulus: totalLulus,
            );
          }

          final item = _historyList[index - 1];
          final dt = item.submittedAt;
          final dateStr = IndoDateFormatter.formatHariTanggal(
            dt.toIso8601String(),
            shortMonth: true,
          );
          final tz = IndoDateFormatter.detectTimeZone(null);
          final timeStr =
              '$dateStr • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $tz';
          final isPassed = item.isPassed;
          final totalSoal = item.totalSoal > 0
              ? item.totalSoal
              : (item.totalBenar + item.totalSalah + item.totalKosong);
          final accuracy = totalSoal > 0
              ? ((item.totalBenar / totalSoal) * 100).round()
              : 0;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isPassed
                    ? const Color(0xFFA5D6A7).withValues(alpha: 0.8)
                    : const Color(0xFFE0E0E0),
                width: isPassed ? 1.4 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Baris Atas: Kategori Badge & Tanggal Ujian
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCategoryPill(item.kategori),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Bagian Utama: Nama Paket & Hero Skor
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.namaPaket,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: isPassed
                                      ? AppColors.paleGreen
                                      : const Color(0xFFFFEBEE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPassed
                                          ? Icons.check_circle_rounded
                                          : Icons.cancel_rounded,
                                      size: 11,
                                      color: isPassed
                                          ? AppColors.primaryGreen
                                          : AppColors.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.statusKelulusan,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isPassed
                                            ? AppColors.primaryGreen
                                            : AppColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (item.predikat.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.grey100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Predikat: ${item.predikat}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.grey700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Skor Hero Pill (Harmonisasi Brand ExamGo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? AppColors.paleGreen
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPassed
                              ? const Color(0xFFA5D6A7)
                              : const Color(0xFFFFCDD2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SKOR',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isPassed
                                  ? AppColors.primaryGreen
                                  : AppColors.error,
                            ),
                          ),
                          Text(
                            '${item.finalScore}',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isPassed
                                  ? AppColors.primaryGreen
                                  : AppColors.error,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            '/ ${item.maxScore}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Visual Segmented Accuracy Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 5,
                    child: Row(
                      children: [
                        if (item.totalBenar > 0)
                          Expanded(
                            flex: item.totalBenar,
                            child: Container(color: AppColors.primaryGreen),
                          ),
                        if (item.totalSalah > 0)
                          Expanded(
                            flex: item.totalSalah,
                            child: Container(color: AppColors.error),
                          ),
                        if (item.totalKosong > 0)
                          Expanded(
                            flex: item.totalKosong,
                            child: Container(color: AppColors.grey300),
                          ),
                        if (totalSoal == 0)
                          Expanded(child: Container(color: AppColors.grey100)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Rincian Metrik Statistik Modern (Harmonisasi Brand ExamGo)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.grey300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCardStatItem(
                        Icons.check_circle_rounded,
                        '${item.totalBenar} Benar',
                        AppColors.primaryGreen,
                      ),
                      _buildCardStatItem(
                        Icons.cancel_rounded,
                        '${item.totalSalah} Salah',
                        AppColors.error,
                      ),
                      _buildCardStatItem(
                        Icons.remove_circle_outline_rounded,
                        '${item.totalKosong} Kosong',
                        AppColors.textSecondary,
                      ),
                      _buildCardStatItem(
                        Icons.percent_rounded,
                        '$accuracy% Akurasi',
                        AppColors.primaryGreen,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Tombol Aksi: Redesain Proposional & Harmonis dengan Brand ExamGo
                Row(
                  children: [
                    Expanded(
                      flex: item.allowRetake ? 3 : 1,
                      child: SizedBox(
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF1B5E20),
                                AppColors.primaryGreen,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryGreen.withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TryoutDiscussionScreen(
                                    title: item.namaPaket,
                                    kategori: item.kategori,
                                    questions: item.questions,
                                    studentAnswers: item.jawaban,
                                    score: item.finalScore,
                                    statusKelulusan: item.statusKelulusan,
                                    returnToDashboardOnExit: false,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.auto_stories_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Pembahasan',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.white,
                                //letterSpacing: 0.2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (item.allowRetake) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final match = _allSchedules
                                  .where((s) => s.paketId == item.token)
                                  .firstOrNull;
                              final targetSched =
                                  match ??
                                  TryoutSchedule(
                                    paketId: item.token,
                                    namaPaket: item.namaPaket,
                                    jenisTest: item.kategori,
                                    tanggal: '',
                                    isLifetime: true,
                                    allowRetake: true,
                                  );
                              final shouldStart = await TryoutDetailSheet.show(
                                context,
                                targetSched,
                              );
                              if (shouldStart == true && context.mounted) {
                                _startTryout(targetSched);
                              }
                            },
                            icon: const Icon(
                              Icons.replay_rounded,
                              size: 16,
                              color: AppColors.primaryGreen,
                            ),
                            label: Text(
                              'Ulangi',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.paleGreen.withValues(
                                alpha: 0.6,
                              ),
                              side: const BorderSide(
                                color: AppColors.primaryGreen,
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryHeaderStats({
    required int totalUjian,
    required int avgScore,
    required int highestScore,
    required int totalLulus,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ringkasan Capaian Tryout',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$totalLulus / $totalUjian Lulus PG',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildHeaderStatItem(
                'Total Sesi',
                '$totalUjian',
                Icons.assignment_turned_in_rounded,
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              _buildHeaderStatItem(
                'Rata-Rata Skor',
                '$avgScore',
                Icons.trending_up_rounded,
              ),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              _buildHeaderStatItem(
                'Skor Tertinggi',
                '$highestScore',
                Icons.emoji_events_rounded,
                isGold: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatItem(
    String label,
    String value,
    IconData icon, {
    bool isGold = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isGold
                    ? const Color(0xFFFDE047)
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isGold ? const Color(0xFFFDE047) : Colors.white,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(String kategori) {
    final kat = kategori.trim().toUpperCase();
    Color bg = AppColors.paleGreen;
    Color text = AppColors.primaryGreen;
    Color border = const Color(0xFFA5D6A7);
    String label = kat;

    if (kat.contains('SNBT') || kat.contains('UTBK')) {
      bg = AppColors.paleGreen;
      text = AppColors.primaryGreen;
      border = const Color(0xFFA5D6A7);
      label = 'UTBK • SNBT';
    } else if (kat.contains('SKD')) {
      bg = const Color(0xFFF1F8E9);
      text = const Color(0xFF33691E);
      border = const Color(0xFFC5E1A5);
      label = 'CAT • BKN SKD';
    } else if (kat.contains('TKA')) {
      bg = const Color(0xFFFFF8E1);
      text = const Color(0xFFE65100);
      border = const Color(0xFFFFECB3);
      label = kat;
    } else if (kat.contains('EVENT')) {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFB45309);
      border = const Color(0xFFFDE68A);
      label = 'EVENT KHUSUS';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: text,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildCardStatItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCatalogState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 48,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Belum Ada Jadwal Tryout',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedCategory == 'Semua'
                    ? 'Paket tryout resmi admin akan segera dijadwalkan.'
                    : 'Tidak ada tryout untuk kategori $_selectedCategory.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
