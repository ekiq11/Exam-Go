import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:examgo/constant/app_config.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:examgo/widget/slide_to_unblock.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── Konstanta Warna & Style ──────────────────────────────────────────────────
const _kGreen  = Color(0xFF2E7D32);
const _kGreenL = Color(0xFF43A047);
const _kBg     = Color(0xFFF0F4F8);

// ─── Konfigurasi Tipe Log ─────────────────────────────────────────────────────
class _ActivityType {
  final IconData icon;
  final Color color;
  final String label;
  const _ActivityType({required this.icon, required this.color, required this.label});
}

const _activityTypes = <String, _ActivityType>{
  'EXIT_APP':      _ActivityType(icon: Icons.exit_to_app_rounded,   color: Color(0xFFE53935), label: 'Keluar Aplikasi'),
  'EXIT_ATTEMPT':  _ActivityType(icon: Icons.logout_rounded,         color: Color(0xFFFF6F00), label: 'Percobaan Keluar'),
  'SCREENSHOT':    _ActivityType(icon: Icons.screenshot_monitor,     color: Color(0xFF8E24AA), label: 'Percobaan Screenshot'),
  'SCREEN_HIDDEN': _ActivityType(icon: Icons.visibility_off_rounded, color: Color(0xFF1565C0), label: 'Layar Tersembunyi'),
  'ACTIVE':        _ActivityType(icon: Icons.play_circle_rounded,    color: Color(0xFF2E7D32), label: 'Mulai Ujian'),
  'FINISHED':      _ActivityType(icon: Icons.check_circle_rounded,   color: Color(0xFF1976D2), label: 'Selesai Ujian'),
  'BLOCKED':       _ActivityType(icon: Icons.block_rounded,          color: Color(0xFFE53935), label: 'Diblokir'),
  'INFO':          _ActivityType(icon: Icons.info_rounded,           color: Color(0xFF0288D1), label: 'Info Sistem'),
};

_ActivityType _getActivityType(String type) =>
    _activityTypes[type] ??
    const _ActivityType(icon: Icons.radio_button_checked, color: Color(0xFF607D8B), label: 'Aktivitas');

// ─── Daftar Sesi Ujian (List Screen) ─────────────────────────────────────────
class TeacherMonitoringListScreen extends StatefulWidget {
  const TeacherMonitoringListScreen({super.key});
  @override
  State<TeacherMonitoringListScreen> createState() => _TeacherMonitoringListScreenState();
}

class _TeacherMonitoringListScreenState extends State<TeacherMonitoringListScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, String>> _history = [];
  bool _loading = true;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _loadHistory();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    final parsed = list.map((item) {
      final parts = item.split('|');
      return {
        'examId':    parts.isNotEmpty     ? parts[0] : '',
        'title':     parts.length > 1 ? parts[1] : 'Ujian',
        'timestamp': parts.length > 2 ? parts[2] : '0',
      };
    }).toList();
    if (mounted) setState(() { _history = parsed; _loading = false; });
  }

  Future<void> _confirmDelete(Map<String, String> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_rounded, color: Colors.red.shade600, size: 32),
              ),
              const SizedBox(height: 16),
              Text('Hapus Sesi Ujian?',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              Text('Sesi "${item['title']}" beserta seluruh data siswa dan log aktivitasnya akan dihapus permanen.',
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('Ya, Hapus', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    await _deleteSession(item['examId']!);
  }

  Future<void> _deleteSession(String examId) async {
    await MonitoringService.instance.deleteExamSession(examId);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('teacher_exam_history') ?? [];
    list.removeWhere((e) => e.startsWith(examId));
    await prefs.setStringList('teacher_exam_history', list);
    if (mounted) {
      setState(() => _history.removeWhere((e) => e['examId'] == examId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text('Sesi ujian berhasil dihapus', style: GoogleFonts.poppins()),
          ],
        ),
        backgroundColor: _kGreenL,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Gradient SliverAppBar ──────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            stretch: true,
            backgroundColor: _kGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                'Monitoring Ujian',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF43A047)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -40, right: -40,
                    child: Container(
                      width: 180, height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20, left: -20,
                    child: Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 50, right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(Icons.monitor_heart_rounded, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                        const SizedBox(height: 4),
                        Text(
                          '${_history.length} Sesi Ujian',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Body ──────────────────────────────────────────────
          _loading
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: _kGreenL)),
                )
              : _history.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.grey.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
                                ],
                              ),
                              child: Icon(Icons.qr_code_2_rounded, size: 72, color: Colors.grey.shade300),
                            ),
                            const SizedBox(height: 24),
                            Text('Belum Ada Sesi Ujian',
                                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                            const SizedBox(height: 8),
                            Text('Buat QR Code ujian terlebih dahulu\npada mode guru untuk memulai monitoring.',
                                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final item = _history[i];
                            final ts = int.tryParse(item['timestamp'] ?? '0') ?? 0;
                            final date = DateTime.fromMillisecondsSinceEpoch(ts);
                            return _buildSessionCard(item, date, i);
                          },
                          childCount: _history.length,
                        ),
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, String> item, DateTime date, int index) {
    final dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
    final dayName = dayNames[date.weekday - 1];
    final monthName = monthNames[date.month - 1];
    final dateStr = '$dayName, ${date.day} $monthName ${date.year}';
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: Key(item['examId']!),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDelete(item);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade300, Colors.red.shade600],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text('Hapus', style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => TeacherMonitoringDetailScreen(
                examId: item['examId']!,
                title: item['title']!,
              ),
            )),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  // Icon Container
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kGreen, _kGreenL],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: _kGreenL.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Icon(Icons.qr_code_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] ?? 'Ujian',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(dateStr, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(timeStr, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Live', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: _kGreen)),
                      ),
                      const SizedBox(height: 10),
                      const Icon(Icons.chevron_right_rounded, color: _kGreenL, size: 22),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Detail Sesi Ujian (Daftar Siswa) ────────────────────────────────────────
class TeacherMonitoringDetailScreen extends StatefulWidget {
  final String examId;
  final String title;

  const TeacherMonitoringDetailScreen({
    super.key,
    required this.examId,
    required this.title,
  });

  @override
  State<TeacherMonitoringDetailScreen> createState() => _TeacherMonitoringDetailScreenState();
}

class _TeacherMonitoringDetailScreenState extends State<TeacherMonitoringDetailScreen>
    with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  String _selectedFilter = 'Semua';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _registerTokenForThisExam();
  }

  /// Mendaftarkan token guru HANYA untuk ujian ini, agar notifikasi terisolasi per pengawas.
  Future<void> _registerTokenForThisExam() async {
    if (AppConfig.gasUrl.isEmpty || AppConfig.gasApiKey.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse(AppConfig.gasUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'apiKey': AppConfig.gasApiKey,
          'action': 'registerToken',
          'token':  token,
          'examId': widget.examId,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: StreamBuilder<QuerySnapshot>(
        stream: MonitoringService.instance.streamExamStudents(widget.examId),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          // ── Hitung Metrik ────────────────────────────────────
          int activeCount   = 0;
          int blockedCount  = 0;
          int finishedCount = 0;
          int offlineCount  = 0;
          int violationTotal = 0;
          int lowBatteryCount = 0;

          final allStudents = docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final rawName = data['name'] as String?;
            final name = (rawName == null || rawName.trim().isEmpty) ? 'Anonim' : rawName;
            final rawNis = data['nis'] as String?;
            final nis = (rawNis == null || rawNis.trim().isEmpty) ? '-' : rawNis;
            final status = data['status'] as String? ?? 'OFFLINE';
            final violations = data['violations'] as int? ?? 0;
            final battery = data['battery_level'] as int? ?? 0;
            final lastPing = data['last_ping'] as Timestamp?;

            final isOffline = lastPing == null ||
                DateTime.now().difference(lastPing.toDate()).inMinutes > 10;
            final displayStatus = isOffline ? 'OFFLINE' : status;

            return {
              'name': name,
              'nis': nis,
              'status': displayStatus,
              'violations': violations,
              'battery': battery,
              'last_ping': lastPing,
              'data': data,
            };
          }).toList();

          for (var s in allStudents) {
            final st = s['status'] as String;
            if (st == 'ACTIVE') {
              activeCount++;
            } else if (st == 'BLOCKED') {
              blockedCount++;
            } else if (st == 'FINISHED') {
              finishedCount++;
            } else {
              offlineCount++;
            }
            violationTotal += s['violations'] as int;
            if ((s['battery'] as int) <= 20) { lowBatteryCount++; }
          }

          // Filter
          final filteredStudents = allStudents.where((s) {
            final q = _searchQuery.toLowerCase();
            final nameMatch = (s['name'] as String).toLowerCase().contains(q);
            final nisMatch  = (s['nis']  as String).toLowerCase().contains(q);
            if (!nameMatch && !nisMatch) return false;
            switch (_selectedFilter) {
              case 'Aktif':     return s['status'] == 'ACTIVE';
              case 'Melanggar': return (s['violations'] as int) > 0 || s['status'] == 'BLOCKED';
              case 'Selesai':   return s['status'] == 'FINISHED';
              case 'Offline':   return s['status'] == 'OFFLINE';
              default:          return true;
            }
          }).toList();

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              // ── Custom SliverAppBar ──────────────────────────
              SliverAppBar(
                expandedHeight: 210,
                pinned: true,
                stretch: true,
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Container(
                    height: 20,
                    decoration: const BoxDecoration(
                      color: _kBg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                  ),
                ),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final top = constraints.biggest.height;
                    // tolerance of 40px for the bottom curve
                    final isCollapsed = top <= kToolbarHeight + MediaQuery.of(context).padding.top + 40;
                    return FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      centerTitle: false,
                      titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                      expandedTitleScale: 1.0,
                      title: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isCollapsed ? 1.0 : 0.0,
                        child: Text(widget.title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                      background: Stack(
                    children: [
                      // Elegant Background Pattern / Gradient
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      Positioned(
                        top: -40, right: -40,
                        child: Container(
                          width: 150, height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 50, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(width: 6, height: 6,
                                          decoration: const BoxDecoration(color: Color(0xFF69F0AE), shape: BoxShape.circle)),
                                        const SizedBox(width: 6),
                                        Text('LIVE', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const _LiveClockText(color: Colors.white70),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.title,
                                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${docs.length} Peserta Terdaftar',
                                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
                              ),
                            ],
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
            body: Column(
              children: [
                // ── Dashboard Metrik ──────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Column(
                    children: [
                      _buildTopMetricRow(
                        activeCount, blockedCount, finishedCount, offlineCount, docs.length,
                      ),
                      const SizedBox(height: 10),
                      _buildBottomMetricRow(violationTotal, lowBatteryCount, docs.length),
                    ],
                  ),
                ),

                // ── Search & Filter ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    children: [
                      // Search
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: TextField(
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: 'Cari nama atau NIS siswa...',
                            hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
                            prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded, color: Colors.grey.shade400),
                                    onPressed: () => setState(() => _searchQuery = ''),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in ['Semua', 'Aktif', 'Melanggar', 'Selesai', 'Offline'])
                              _buildFilterChip(f),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── List Siswa ─────────────────────────────────
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator(color: _kGreenL))
                      : snapshot.hasError
                          ? Center(child: Text('Error: ${snapshot.error}'))
                          : filteredStudents.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: filteredStudents.length,
                                  itemBuilder: (context, index) =>
                                      _buildStudentCard(filteredStudents[index]),
                                ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopMetricRow(int active, int blocked, int finished, int offline, int total) {
    return Row(
      children: [
        _buildMetricTile('Aktif', active, total, Icons.wifi_rounded, const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
        const SizedBox(width: 10),
        _buildMetricTile('Melanggar', blocked, total, Icons.block_rounded, Colors.red.shade700, Colors.red.shade50),
        const SizedBox(width: 10),
        _buildMetricTile('Selesai', finished, total, Icons.check_circle_rounded, Colors.blue.shade700, Colors.blue.shade50),
        const SizedBox(width: 10),
        _buildMetricTile('Offline', offline, total, Icons.cloud_off_rounded, Colors.grey.shade600, Colors.grey.shade100),
      ],
    );
  }

  Widget _buildMetricTile(String label, int count, int total, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text('$count',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color, height: 1)),
            Text(label,
                style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomMetricRow(int violations, int lowBattery, int total) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
            bg: Colors.orange.shade50,
            label: 'Pelanggaran',
            value: violations.toString(),
            subtitle: 'dari $total siswa',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInfoCard(
            icon: Icons.battery_alert_rounded,
            color: Colors.red.shade600,
            bg: Colors.red.shade50,
            label: 'Baterai',
            value: lowBattery.toString(),
            subtitle: 'di bawah 20%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildInfoCard(
            icon: Icons.people_alt_rounded,
            color: Colors.indigo.shade600,
            bg: Colors.indigo.shade50,
            label:'Peserta',
            value: total.toString(),
            subtitle: 'terdaftar',
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color color,
    required Color bg,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87, height: 1)),
                Text(label, style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = _selectedFilter == filter;
    final filterColors = {
      'Aktif':     _kGreen,
      'Melanggar': Colors.red.shade600,
      'Selesai':   Colors.blue.shade600,
      'Offline':   Colors.grey.shade600,
      'Semua':     Colors.blueGrey.shade700,
    };
    final color = filterColors[filter] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: FilterChip(
          label: Text(filter,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade600,
              )),
          selected: isSelected,
          onSelected: (_) => setState(() => _selectedFilter = filter),
          selectedColor: color.withValues(alpha: 0.12),
          checkmarkColor: color,
          backgroundColor: Colors.white,
          elevation: isSelected ? 0 : 1,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: StadiumBorder(
            side: BorderSide(
              color: isSelected ? color : Colors.grey.shade200,
              width: isSelected ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Tidak ada siswa ditemukan',
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text('Coba ubah filter atau kata kunci pencarian',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> s) {
    final name       = s['name'] as String;
    final nis        = s['nis']  as String;
    final status     = s['status'] as String;
    final violations = s['violations'] as int;
    final battery    = s['battery'] as int;
    final lastPing   = s['last_ping'] as Timestamp?;

    // ── Status Config ────────────────────────────────────
    late Color statusColor;
    late Color statusBg;
    late IconData statusIcon;
    late String statusLabel;

    switch (status) {
      case 'ACTIVE':
        statusColor = const Color(0xFF2E7D32); statusBg = const Color(0xFFE8F5E9);
        statusIcon = Icons.wifi_rounded; statusLabel = 'Aktif';
        break;
      case 'PAUSED':
        statusColor = Colors.orange.shade700; statusBg = Colors.orange.shade50;
        statusIcon = Icons.pause_circle_rounded; statusLabel = 'Jeda';
        break;
      case 'FINISHED':
        statusColor = Colors.blue.shade700; statusBg = Colors.blue.shade50;
        statusIcon = Icons.check_circle_rounded; statusLabel = 'Selesai';
        break;
      case 'BLOCKED':
        statusColor = Colors.red.shade700; statusBg = Colors.red.shade50;
        statusIcon = Icons.block_rounded; statusLabel = 'Diblokir';
        break;
      default:
        statusColor = Colors.grey.shade600; statusBg = Colors.grey.shade100;
        statusIcon = Icons.cloud_off_rounded; statusLabel = 'Offline';
    }

    final isBlocked = status == 'BLOCKED';
    final hasViolation = violations > 0;

    // Last ping string
    String pingStr = 'Belum ada data';
    if (lastPing != null) {
      final diff = DateTime.now().difference(lastPing.toDate());
      if (diff.inSeconds < 60) {
        pingStr = 'Baru saja';
      } else if (diff.inMinutes < 60) {
        pingStr = '${diff.inMinutes} mnt lalu';
      } else {
        pingStr = '${diff.inHours} jam lalu';
      }
    }

    // Battery icon & color
    final batIcon  = battery > 50 ? Icons.battery_full_rounded
                   : battery > 20 ? Icons.battery_4_bar_rounded
                   :                Icons.battery_alert_rounded;
    final batColor = battery > 50 ? Colors.green.shade600
                   : battery > 20 ? Colors.orange.shade600
                   :                Colors.red.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBlocked
              ? Colors.red.shade200
              : hasViolation
                  ? Colors.orange.shade200
                  : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isBlocked
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => StudentActivityLogScreen(
                examId: widget.examId,
                nis: nis,
                name: name,
                status: status,
                violations: violations,
              ),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    // ── Avatar with status ring ──────────────
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: statusBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 2),
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -2, right: -2,
                          child: Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(statusIcon, size: 10, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // ── Name & NIS ───────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('NIS: $nis',
                                    style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Status Badge ─────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(statusLabel,
                              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                        ),
                        const SizedBox(height: 6),
                        if (hasViolation)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.warning_rounded, color: Colors.white, size: 10),
                                const SizedBox(width: 3),
                                Text('$violations Pelanggaran',
                                    style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // ── Info Row: Battery & Last Ping ────────────
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(batIcon, size: 15, color: batColor),
                      const SizedBox(width: 4),
                      Text('$battery%', style: GoogleFonts.poppins(fontSize: 11, color: batColor, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(pingStr, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                      Text('Lihat Log', style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade400)),
                    ],
                  ),
                ),

                // ── Unblock Button ─────────────────────────
                if (isBlocked) ...[
                  const SizedBox(height: 12),
                  SlideToUnblock(
                    onAction: () => _showUnblockConfirmation(context, widget.examId, nis, name),
                    text: 'Geser untuk Buka Akses',
                    backgroundColor: Colors.red.shade50,
                    sliderColor: Colors.red.shade600,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Halaman Log Aktivitas Siswa ──────────────────────────────────────────────
class StudentActivityLogScreen extends StatefulWidget {
  final String examId;
  final String nis;
  final String name;
  final String status;
  final int violations;

  const StudentActivityLogScreen({
    super.key,
    required this.examId,
    required this.nis,
    required this.name,
    required this.status,
    required this.violations,
  });

  @override
  State<StudentActivityLogScreen> createState() => _StudentActivityLogScreenState();
}

class _StudentActivityLogScreenState extends State<StudentActivityLogScreen> {
  Color get _statusColor {
    switch (widget.status) {
      case 'ACTIVE':   return const Color(0xFF2E7D32);
      case 'PAUSED':   return Colors.orange.shade700;
      case 'BLOCKED':  return Colors.red.shade700;
      case 'FINISHED': return Colors.blue.shade700;
      default:         return Colors.grey.shade600;
    }
  }

  String get _statusLabel {
    switch (widget.status) {
      case 'ACTIVE':   return 'Sedang Aktif';
      case 'PAUSED':   return 'Dijeda';
      case 'BLOCKED':  return 'Diblokir';
      case 'FINISHED': return 'Selesai Ujian';
      default:         return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: widget.status == 'BLOCKED'
          ? Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -4)),
                ],
              ),
              child: SlideToUnblock(
                onAction: () => _unblockStudent(context),
              ),
            )
          : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── AppBar ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(20),
              child: Container(
                height: 20,
                decoration: const BoxDecoration(
                  color: _kBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
              ),
            ),
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final top = constraints.biggest.height;
                final isCollapsed = top <= kToolbarHeight + MediaQuery.of(context).padding.top + 40;
                return FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                  expandedTitleScale: 1.0,
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isCollapsed ? 1.0 : 0.0,
                    child: Text(widget.name, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                  background: Stack(
                children: [
                  // Elegant Background Pattern / Gradient
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -40, right: -40,
                    child: Container(
                      width: 150, height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 50, 20, 32), // Top padding 50 to avoid title overlap
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Avatar Row
                          Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
                                    style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.name,
                                        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text('NIS: ${widget.nis}',
                                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        // Status & Violation Badges
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _statusColor,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: _statusColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                              ),
                              child: Text(_statusLabel,
                                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                            const SizedBox(width: 10),
                            if (widget.violations > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  border: Border.all(color: Colors.red.shade200),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning_rounded, size: 14, color: Colors.red.shade700),
                                    const SizedBox(width: 6),
                                    Text('${widget.violations} Pelanggaran',
                                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),

          // ── Log Timeline Header ───────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.timeline_rounded, size: 18, color: _kGreenL),
                  const SizedBox(width: 8),
                  Text('Log Aktivitas Real-Time',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF69F0AE).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(width: 6, height: 6,
                            decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('Live', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: _kGreen)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Log Stream ────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: MonitoringService.instance.streamStudentActivityLog(widget.examId, widget.nis),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: _kGreenL)),
                );
              }

              final logs = snapshot.data?.docs ?? [];
              if (logs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4))],
                          ),
                          child: Icon(Icons.history_toggle_off_rounded, size: 56, color: Colors.grey.shade300),
                        ),
                        const SizedBox(height: 20),
                        Text('Belum Ada Aktivitas',
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                        const SizedBox(height: 8),
                        Text('Log akan muncul secara otomatis\nketika siswa melakukan aktivitas selama ujian.',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade400),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final data = logs[i].data() as Map<String, dynamic>;
                      final type  = data['activity_type'] as String? ?? 'INFO';
                      final desc  = data['description']   as String? ?? '-';
                      final ts    = data['timestamp']      as Timestamp?;
                      final at    = _getActivityType(type);
                      final timeStr = ts != null ? _formatTime(ts.toDate()) : '–';
                      final dateStr = ts != null ? _formatDate(ts.toDate()) : '';
                      return _LogItem(
                        icon: at.icon,
                        color: at.color,
                        label: at.label,
                        description: desc,
                        time: timeStr,
                        date: dateStr,
                        isFirst: i == 0,
                        isLast: i == logs.length - 1,
                      );
                    },
                    childCount: logs.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _unblockStudent(BuildContext context) {
    _showUnblockConfirmation(context, widget.examId, widget.nis, widget.name, onSuccess: () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─── Widget Log Item (Timeline) ───────────────────────────────────────────────
class _LogItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final String time;
  final String date;
  final bool isFirst;
  final bool isLast;

  const _LogItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.time,
    required this.date,
    this.isFirst = false,
    this.isLast  = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline Column ──────────────────────────────
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Line above dot (hidden for first)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: isFirst ? Colors.transparent : Colors.grey.shade200,
                    ),
                  ),
                ),
                // Dot
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isFirst ? color : color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: isFirst
                        ? Border.all(color: color, width: 0)
                        : Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
                    boxShadow: isFirst
                        ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                        : null,
                  ),
                  child: Icon(icon, color: isFirst ? Colors.white : color, size: 17),
                ),
                // Line below dot (hidden for last)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : Colors.grey.shade200,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ── Log Card Content ─────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isFirst ? color.withValues(alpha: 0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFirst ? color.withValues(alpha: 0.25) : Colors.grey.shade100,
                    width: isFirst ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isFirst ? 0.06 : 0.03),
                      blurRadius: isFirst ? 12 : 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Label + Time Row
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                label,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: color,
                                ),
                              ),
                              if (isFirst) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Terbaru',
                                      style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(time, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                            if (date.isNotEmpty)
                              Text(date, style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.grey.shade400)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Description
                    Text(
                      description,
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widget Jam Real-Time ─────────────────────────────────────────────────────
class _LiveClockText extends StatefulWidget {
  final Color? color;
  const _LiveClockText({this.color});

  @override
  State<_LiveClockText> createState() => _LiveClockTextState();
}

class _LiveClockTextState extends State<_LiveClockText> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return Text(
      '$h:$m:$s',
      style: GoogleFonts.poppins(fontSize: 13, color: widget.color ?? Colors.white.withValues(alpha: 0.85)),
    );
  }
}

// ─── Helper Konfirmasi Buka Blokir ────────────────────────────────────────────
Future<void> _showUnblockConfirmation(BuildContext context, String examId, String nis, String name, {VoidCallback? onSuccess}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_open_rounded, color: _kGreen, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Yakin Buka Blokir?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Akses ujian untuk $name (NIS: $nis) akan dibuka kembali.',
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text('Batal', style: GoogleFonts.poppins(color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text('Ya, Buka', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  MonitoringService.instance.updateStudentStatus(
    examId: examId,
    nis: nis, name: name,
    status: 'ACTIVE', violations: 0,
  );
  MonitoringService.instance.logActivity(
    examId: examId,
    nis: nis,
    activityType: 'INFO',
    description: 'Pengawas membuka akses siswa',
  );

  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(
      children: [
        const Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text('Akses $name berhasil dibuka', style: GoogleFonts.poppins()),
      ],
    ),
    backgroundColor: _kGreenL,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
  ));

  if (onSuccess != null) {
    onSuccess();
  }
}
