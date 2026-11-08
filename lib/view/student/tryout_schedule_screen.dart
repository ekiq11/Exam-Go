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
import 'package:examgo/view/student/widgets/tryout_card_widget.dart';
import 'package:examgo/view/student/widgets/tryout_detail_sheet.dart';

/// Halaman Katalog Paket & Jadwal Tryout Nasional serta Riwayat & Pembahasan
class TryoutScheduleScreen extends StatefulWidget {
  const TryoutScheduleScreen({super.key});

  @override
  State<TryoutScheduleScreen> createState() => _TryoutScheduleScreenState();
}

class _TryoutScheduleScreenState extends State<TryoutScheduleScreen> with SingleTickerProviderStateMixin {
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
    await Future.wait([
      _loadSchedules(),
      _loadHistory(),
    ]);
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
      return s.jenisTest.contains(category) || s.namaPaket.toUpperCase().contains(category);
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
              child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFFD97706), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Masuk Tiket Event',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
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
              style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tokenCtrl,
              textCapitalization: TextCapitalization.characters,
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1),
              decoration: InputDecoration(
                hintText: 'Misal: EVENT-ABCD-1234',
                hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey)),
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
              if (res.isSuccess || res.message.contains('aktif kembali') || raw.startsWith('EVENT')) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDashboardScreen(
                      eventId: target,
                      eventToken: raw,
                    ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Buka Event', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
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
              child: const Icon(Icons.confirmation_number_outlined, color: Colors.white, size: 18),
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
              child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
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
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
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
                child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFBBF24), size: 24),
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
                    color: isSelected ? AppColors.primaryGreen : const Color(0xFFE2E8F0),
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
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
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
                                  TryoutDetailSheet.show(context, item);
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

  Widget _buildHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen));
    }

    if (_historyList.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _loadHistory,
        child: ListView(
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
                      Icons.history_edu_rounded,
                      size: 48,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum Ada Riwayat Tryout',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kerjakan paket tryout di tab Daftar Tryout.\nHasil pengerjaan & pembahasan akan tersimpan otomatis di sini.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _historyList.length,
        itemBuilder: (context, index) {
          final item = _historyList[index];
          final dt = item.submittedAt;
          final dateStr = IndoDateFormatter.formatHariTanggal(dt.toIso8601String(), shortMonth: true);
          final tz = IndoDateFormatter.detectTimeZone(null);
          final timeStr = '$dateStr • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $tz';
          final isPassed = item.isPassed;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isPassed ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                width: isPassed ? 1.4 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isPassed ? Icons.stars_rounded : Icons.info_outline_rounded,
                        color: isPassed ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.namaPaket,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            timeStr,
                            style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.finalScore}',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isPassed ? const Color(0xFF15803D) : const Color(0xFFBE123C),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.statusKelulusan,
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isPassed ? const Color(0xFF166534) : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Ringkasan Benar / Salah / Kosong
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text(
                        '✅ ${item.totalBenar} Benar',
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF166534)),
                      ),
                      Text(
                        '❌ ${item.totalSalah} Salah',
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B)),
                      ),
                      Text(
                        '⚪ ${item.totalKosong} Kosong',
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Aksi: Lihat Pembahasan & Kerjakan Ulang
                Row(
                  children: [
                    Expanded(
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
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: Text(
                          'Lihat Pembahasan 📖',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    if (item.allowRetake) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          // Temukan schedule yang cocok untuk dikerjakan ulang
                          final match = _allSchedules.where((s) => s.paketId == item.token).firstOrNull;
                          if (match != null) {
                            TryoutDetailSheet.show(context, match);
                          } else {
                            // Fallback jika paket tidak di jadwal umum
                            final synthSchedule = TryoutSchedule(
                              paketId: item.token,
                              namaPaket: item.namaPaket,
                              jenisTest: item.kategori,
                              tanggal: '',
                              isLifetime: true,
                              allowRetake: true,
                            );
                            TryoutDetailSheet.show(context, synthSchedule);
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          'Kerjakan Ulang',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E293B),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
