import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/services/exam_cache_service.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/services/tryout_schedule_service.dart';
import 'package:examgo/utils/indo_date_formatter.dart';
import 'package:examgo/utils/token_input_formatter.dart';
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
  bool _isSyncing = false;
  List<TryoutSchedule> _allSchedules = [];
  List<StudentTryoutHistoryItem> _historyList = [];
  Set<String> _cachedPaketIds = {};
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
    // 1. TAHAP INSTAN: Muat cache lokal (< 20ms) agar pengguna langsung melihat daftar paket
    final cached = await TryoutScheduleService.instance.getCachedSchedules();
    final cachedIds = await ExamCacheService.instance.getCachedPackageIds();
    if (mounted) {
      setState(() {
        if (cached.isNotEmpty) {
          _allSchedules = cached;
          _isLoading = false;
        }
        _cachedPaketIds = cachedIds.toSet();
        _isSyncing = true;
      });
    }

    // 2. TAHAP SINKRONISASI: Ambil data real-time langsung dari Firestore
    try {
      final fresh = await TryoutScheduleService.instance.getActiveSchedules(forceRefresh: true);
      final freshCachedIds = await ExamCacheService.instance.getCachedPackageIds();
      if (mounted) {
        setState(() {
          _allSchedules = fresh;
          _cachedPaketIds = freshCachedIds.toSet();
          _isLoading = false;
          _isSyncing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSyncing = false;
        });
      }
    }

    // 3. Muat Riwayat & Nilai Siswa
    await _loadHistory();
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
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => const _EventTokenDialog(),
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
              ? _buildCatalogLoadingState()
              : Column(
                  children: [
                    // Indikator Sinkronisasi Firestore Real-Time
                    if (_isSyncing)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F5E9),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFC8E6C9), width: 1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(
                              'Menyinkronkan paket tryout dari Cloud Firestore...',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1B5E20),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primaryGreen,
                        onRefresh: _loadData,
                        child: _filteredSchedules.isEmpty
                            ? _buildEmptyCatalogState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                                itemCount: _filteredSchedules.length,
                                itemBuilder: (context, index) {
                                  final item = _filteredSchedules[index];
                                  final isCached = _cachedPaketIds.contains(item.paketId.toUpperCase()) ||
                                      _cachedPaketIds.contains(item.paketId);
                                  return TryoutCardWidget(
                                    schedule: item,
                                    isCached: isCached,
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
                                              isCached: isCached,
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
                ),
        ),
      ],
    );
  }

  Widget _buildCatalogLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Menghubungkan ke Cloud Firestore',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Memuat katalog paket tryout dan jadwal resmi...',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
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

    // 3. Cek apakah paket soal sudah tersimpan di penyimpanan lokal HP
    final isAlreadyCached = await ExamCacheService.instance.isExamCached(schedule.paketId);
    if (!isAlreadyCached && mounted) {
      // Tampilkan dialog proses unduh dan simpan lokal berindikator profesional
      final success = await _showDownloadPreparationDialog(schedule);
      if (!success || !mounted) return;
    }

    // 4. Catat pemakaian 1 kuota ujian
    await LicenseService.instance.recordExamAttempt();

    if (!mounted) return;

    // 5. Masuk ke Sesi Ujian Siswa (Instan karena data telah siap di HP)
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

  /// Dialog unduh & simpan offline dengan indikator persentase & langkah transparan
  Future<bool> _showDownloadPreparationDialog(TryoutSchedule schedule) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) {
            return _ExamDownloadProgressDialog(schedule: schedule);
          },
        ) ??
        false;
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
          return _buildHistoryCard(item);
        },
      ),
    );
  }

  /// Card Riwayat & Hasil Ujian Siswa (Redesain Proposional & Modern)
  Widget _buildHistoryCard(StudentTryoutHistoryItem item) {
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPassed
              ? const Color(0xFFA5D6A7).withValues(alpha: 0.9)
              : const Color(0xFFE2E8F0),
          width: isPassed ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Top Bar: Kategori & Waktu ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCategoryPill(item.kategori),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── 2. Nama Paket & Status Lulus ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.namaPaket,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF0F172A),
                    height: 1.35,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPassed ? AppColors.paleGreen : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPassed ? const Color(0xFFA5D6A7) : const Color(0xFFFFCDD2),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 12,
                            color: isPassed ? AppColors.primaryGreen : AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.statusKelulusan,
                            style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isPassed ? AppColors.primaryGreen : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.predikat.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                        ),
                        child: Text(
                          'Predikat: ${item.predikat}',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── 3. Dedicated Proportional Score Container (Hero Section) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPassed
                      ? [
                          const Color(0xFFF0FDF4),
                          const Color(0xFFDCFCE7),
                        ]
                      : [
                          const Color(0xFFFFF1F2),
                          const Color(0xFFFFE4E6),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPassed ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3),
                ),
              ),
              child: Row(
                children: [
                  // Sisi Kiri: Nilai Akhir
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.military_tech_rounded,
                              size: 14,
                              color: isPassed ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'SKOR AKHIR',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${item.finalScore}',
                                style: GoogleFonts.poppins(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '/ ${item.maxScore}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Garis Pemisah Vertikal
                  Container(
                    width: 1,
                    height: 38,
                    color: isPassed
                        ? const Color(0xFF86EFAC).withValues(alpha: 0.6)
                        : const Color(0xFFFDA4AF).withValues(alpha: 0.6),
                  ),

                  // Sisi Kanan: Akurasi & Total Benar
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pie_chart_rounded,
                                size: 13,
                                color: isPassed ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'AKURASI',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$accuracy%',
                                  style: GoogleFonts.poppins(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'tepat',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── 4. Segmented Accuracy Progress Bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    if (item.totalBenar > 0)
                      Expanded(
                        flex: item.totalBenar,
                        child: Container(color: const Color(0xFF16A34A)),
                      ),
                    if (item.totalSalah > 0)
                      Expanded(
                        flex: item.totalSalah,
                        child: Container(color: const Color(0xFFE11D48)),
                      ),
                    if (item.totalKosong > 0)
                      Expanded(
                        flex: item.totalKosong,
                        child: Container(color: const Color(0xFFCBD5E1)),
                      ),
                    if (totalSoal == 0)
                      Expanded(child: Container(color: const Color(0xFFE2E8F0))),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── 5. Rincian Metrik Statistik Modern ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Benar',
                      value: '${item.totalBenar}',
                      color: const Color(0xFF16A34A),
                      icon: Icons.check_circle_rounded,
                    ),
                  ),
                  Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Salah',
                      value: '${item.totalSalah}',
                      color: const Color(0xFFE11D48),
                      icon: Icons.cancel_rounded,
                    ),
                  ),
                  Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Kosong',
                      value: '${item.totalKosong}',
                      color: const Color(0xFF64748B),
                      icon: Icons.remove_circle_outline_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── 6. Tombol Aksi (Pembahasan & Ulangi) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
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
                            color: AppColors.primaryGreen.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _openDiscussion(item),
                        icon: const Icon(
                          Icons.auto_stories_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Pembahasan & Analisis',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
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
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => _retakeTryout(item),
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
                          backgroundColor: AppColors.paleGreen.withValues(alpha: 0.6),
                          side: const BorderSide(
                            color: AppColors.primaryGreen,
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDiscussion(StudentTryoutHistoryItem item) async {
    var questions = item.questions;
    if (questions.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
      try {
        final cached = await ExamCacheService.instance.loadExam(item.token);
        if (cached != null && cached.questions.isNotEmpty) {
          questions = cached.questions;
        } else {
          final downloaded = await ExamCacheService.instance.downloadAndCacheExam(
            paketId: item.token,
          );
          if (downloaded.questions.isNotEmpty) {
            questions = downloaded.questions;
          }
        }
      } catch (_) {}
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Butir soal pembahasan belum tersedia offline atau di server.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TryoutDiscussionScreen(
          title: item.namaPaket,
          kategori: item.kategori,
          questions: questions,
          studentAnswers: item.jawaban,
          score: item.finalScore,
          statusKelulusan: item.statusKelulusan,
          returnToDashboardOnExit: false,
        ),
      ),
    );
  }

  Future<void> _retakeTryout(StudentTryoutHistoryItem item) async {
    final match = _allSchedules
        .where((s) => s.paketId == item.token)
        .firstOrNull;
    final targetSched = match ??
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
    if (shouldStart == true && mounted) {
      _startTryout(targetSched);
    }
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
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
          colors: [Color(0xFF007F37), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007F37).withValues(alpha: 0.25),
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
                  fontWeight: FontWeight.w700,
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

/// Dialog proses unduh & penyimpanan lokal soal tryout berindikator profesional
class _ExamDownloadProgressDialog extends StatefulWidget {
  final TryoutSchedule schedule;

  const _ExamDownloadProgressDialog({required this.schedule});

  @override
  State<_ExamDownloadProgressDialog> createState() => _ExamDownloadProgressDialogState();
}

class _ExamDownloadProgressDialogState extends State<_ExamDownloadProgressDialog> {
  double _progress = 0.15;
  String _statusMessage = 'Menghubungkan ke Cloud Firestore...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _errorMessage = null;
      _progress = 0.15;
      _statusMessage = 'Menghubungkan ke Cloud Firestore...';
    });

    try {
      await ExamCacheService.instance.downloadAndCacheExam(
        paketId: widget.schedule.paketId,
        initialSchedule: widget.schedule,
        onProgress: (msg, pct) {
          if (mounted) {
            setState(() {
              _statusMessage = msg;
              _progress = pct;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = 'Soal siap dikerjakan!';
        });
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Icon
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: _errorMessage != null
                  ? const Color(0xFFFEE2E2)
                  : AppColors.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _errorMessage != null
                  ? Icons.error_outline_rounded
                  : Icons.cloud_download_rounded,
              color: _errorMessage != null ? Colors.red.shade600 : AppColors.primaryGreen,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            _errorMessage != null ? 'Gagal Menyiapkan Soal' : 'Menyiapkan Lembar Ujian',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),

          Text(
            widget.schedule.namaPaket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 18),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF991B1B),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Coba Lagi', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Progress Bar & Percentage
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _statusMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed_rounded, size: 14, color: Color(0xFF16A34A)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Soal otomatis disimpan ke HP agar hemat kuota & anti-lag.',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dialog Masuk Tiket Event yang harmonis dengan desain ExamGo & PremiumTokenDialog
class _EventTokenDialog extends StatefulWidget {
  const _EventTokenDialog();

  @override
  State<_EventTokenDialog> createState() => _EventTokenDialogState();
}

class _EventTokenDialogState extends State<_EventTokenDialog> {
  final TextEditingController _tokenCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _waCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameCtrl.text = prefs.getString('student_name') ?? '';
        _emailCtrl.text = prefs.getString('student_email') ?? '';
        _waCtrl.text = prefs.getString('student_whatsapp') ?? '';
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _waCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _tokenCtrl.text = data.text!.trim().toUpperCase();
        _errorMessage = null;
      });
    }
  }

  Future<void> _submitToken() async {
    final raw = _tokenCtrl.text.trim().toUpperCase().replaceAll(' ', '');
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final wa = _waCtrl.text.trim();

    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Silakan masukkan kode tiket event Anda');
      return;
    }

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Silakan isi Nama Lengkap untuk data presensi');
      return;
    }

    if (wa.length < 9) {
      setState(() => _errorMessage = 'Silakan masukkan No. WhatsApp aktif (min. 9 digit)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('student_name', name);
      if (email.isNotEmpty) await prefs.setString('student_email', email);
      await prefs.setString('student_whatsapp', wa);

      final res = await LicenseService.instance.activateToken(
        rawToken: raw,
        expectedType: 'STUDENT_LIFETIME',
        userName: name,
        userEmail: email.toLowerCase(),
        userWhatsapp: wa,
      );

      if (!mounted) return;

      final target = res.targetExamId ?? raw;
      if (res.isSuccess ||
          res.message.contains('aktif kembali') ||
          raw.startsWith('EVENT') ||
          raw.startsWith('EV')) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EventDashboardScreen(eventId: target, eventToken: raw),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = res.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Gagal memproses token: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Gradient Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.confirmation_number_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Masuk Tiket Event',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Buka Akses Dashboard Event & Ujian Tryout Resmi',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Form Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kode Tiket / Token Event:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _tokenCtrl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [TokenInputFormatter()],
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1.2,
                          color: const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'EVENT-XXXX-YYYY / EVxxxx',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.vpn_key_rounded,
                            size: 19,
                            color: AppColors.primaryGreen,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.content_paste_rounded,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            tooltip: 'Tempel dari Clipboard',
                            onPressed: _pasteFromClipboard,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primaryGreen,
                              width: 2,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Divider: Data Identitas
                      Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'DATA IDENTITAS PESERTA',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF64748B),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Field: Nama Siswa
                      Text(
                        'Nama Lengkap Siswa:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Misal: Muhammad Rizky',
                          hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 19, color: Color(0xFF64748B)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Field: WhatsApp Siswa
                      Text(
                        'No. WhatsApp Aktif:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _waCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Misal: 081234567890',
                          hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(Icons.phone_android_rounded, size: 19, color: Color(0xFF64748B)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Field: Email
                      Text(
                        'Email (Opsional):',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'nama@email.com',
                          hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(Icons.mail_outline_rounded, size: 19, color: Color(0xFF64748B)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                          ),
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: Text(
                                  'Batal',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submitToken,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Buka Event',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ],
                                      ),
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
        ),
      ),
    );
  }
}
