// ignore_for_file: deprecated_member_use
import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/services/qr_generator.dart';
import 'package:examgo/services/exam_session_service.dart';
import 'package:examgo/view/pre_exam_checklist.dart';
import 'package:examgo/view/qr_scanner.dart';
import 'package:examgo/view/qris_web_view.dart';
import 'package:examgo/view/teacher_mode.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../constant/app_colors.dart';
import '../constant/app_config.dart';
import '../constant/responsive.dart';

// ─────────────────────────────────────────────────────────────────
// _HistoryItem
// ─────────────────────────────────────────────────────────────────
class _HistoryItem {
  final String title;
  final String url;
  const _HistoryItem({required this.title, required this.url});

  String toStorage() => '$title\x00$url';

  static _HistoryItem fromStorage(String raw) {
    final idx = raw.indexOf('\x00');
    if (idx != -1) {
      return _HistoryItem(
        title: raw.substring(0, idx),
        url: raw.substring(idx + 1),
      );
    }
    return _HistoryItem(title: Uri.tryParse(raw)?.host ?? raw, url: raw);
  }

  String get displayLabel =>
      title.trim().isNotEmpty ? title.trim() : Uri.tryParse(url)?.host ?? url;
}

// ─────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _connected = true;
  List<_HistoryItem> _history = [];
  int _logoTapCount = 0; // tap 7x untuk buka Mode Guru

  static const _historyKey = 'scan_history_v3';
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.055).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkConnectivity();
    _listenConnectivity();
    _loadHistory();
    // Cek apakah ada sesi ujian yang tidak selesai (crash recovery)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCrashRecovery());
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    _pulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── Connectivity ─────────────────────────────────────────────

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(() => _connected = !result.contains(ConnectivityResult.none));
    } catch (_) {}
  }

  void _listenConnectivity() {
    _connectSub = Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      final nowConnected = !result.contains(ConnectivityResult.none);
      final wasOffline = !_connected;
      setState(() => _connected = nowConnected);
      if (wasOffline && nowConnected) _showReconnectSnack();
    });
  }

  void _showReconnectSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(
              'Internet tersambung kembali!',
              style: GoogleFonts.poppins(
                fontSize: context.rs(13),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.fromLTRB(
          context.rs(16),
          0,
          context.rs(16),
          context.rs(20),
        ),
      ),
    );
  }

  // ─── Crash Recovery ───────────────────────────────────────────

  Future<void> _checkCrashRecovery() async {
    final session = await ExamSessionService.instance.getActiveSession();
    if (session == null || !mounted) return;

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.restore_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'Sesi Tidak Selesai',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Ujian "${session.title}" ditemukan tidak selesai.\n\nApakah Anda ingin melanjutkan ujian?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Abaikan', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Lanjutkan', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (resume != true || !mounted) {
      await ExamSessionService.instance.clear();
      return;
    }

    // Langsung buka WebView dengan URL dari sesi sebelumnya
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamWebViewScreen(
          url: session.url,
          title: session.title,
        ),
      ),
    );
  }

  // ─── History ──────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_historyKey) ?? [];
      if (!mounted) return;
      setState(() => _history = saved.map(_HistoryItem.fromStorage).toList());
    } catch (_) {}
  }

  Future<void> _saveEntry(_HistoryItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_historyKey) ?? [];
      final dedup = current
          .where((e) => _HistoryItem.fromStorage(e).url != item.url)
          .toList();
      final updated = [
        item.toStorage(),
        ...dedup,
      ].take(AppConfig.maxScanHistory).toList();
      await prefs.setStringList(_historyKey, updated);
      if (!mounted) return;
      setState(() => _history = updated.map(_HistoryItem.fromStorage).toList());
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Hapus Riwayat?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Semua riwayat scan akan dihapus.',
          style: GoogleFonts.poppins(
            fontSize: context.rs(13),
            color: Colors.grey[600],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Batal',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              'Hapus',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
      if (!mounted) return;
      setState(() => _history.clear());
    } catch (_) {}
  }

  // ─── Navigation ───────────────────────────────────────────────

  Future<void> _onScanTap() async {
    if (!_connected) {
      _showError(
        'Tidak Ada Koneksi',
        'Pastikan perangkat terhubung ke internet sebelum ujian.',
      );
      return;
    }
    final encoded = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (encoded == null || encoded.isEmpty || !mounted) return;
    final result = ScanResult.decode(encoded);
    await _saveEntry(_HistoryItem(title: result.title, url: result.url));
    _confirmAndStart(result.url, title: result.title);
  }

  Future<void> _confirmAndStart(String url, {String title = ''}) async {
    if (!mounted) return;
    final displayTitle = title.trim().isNotEmpty
        ? title.trim()
        : Uri.tryParse(url)?.host ?? url;

    // Tampilkan Pre-Exam Checklist Dialog (Cek Baterai, Root/Dev Mode, dan Identitas)
    final identity = await PreExamChecklistDialog.show(context, displayTitle);
    
    // Jika dialog ditutup tanpa memulai, batalkan
    if (identity == null) return;
    if (!mounted) return;

    final name = identity['name'] ?? '';
    final nis  = identity['nis'] ?? '';

    // ── A. Sisipkan identitas ke URL ujian sebagai query parameter ──
    // Server ujian (Google Form / LMS) akan menerima ?peserta=Budi&nis=12345
    // sehingga rekap jawaban otomatis mencatat nama peserta.
    final finalUrl = _appendIdentityToUrl(url, name: name, nis: nis);

    // ── B. Set Firebase Analytics user properties ──────────────────
    // Guru yang punya akses Firebase Console bisa melihat per-user.
    // Juga berguna jika terjadi crash — Crashlytics tahu siapa yang crash.
    AnalyticsService.instance.setStudentIdentity(name: name, nis: nis);

    // Arahkan ke WebView dengan URL yang sudah mengandung identitas
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamWebViewScreen(
          url: finalUrl,
          title: displayTitle,
        ),
      ),
    );
  }

  /// Menambahkan query parameter peserta & nis ke URL ujian.
  /// Jika URL sudah punya query, parameter ditambahkan (tidak menimpa).
  String _appendIdentityToUrl(String url, {required String name, required String nis}) {
    try {
      if (name.isEmpty && nis.isEmpty) return url;
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);
      if (name.isNotEmpty) params['peserta'] = name;
      if (nis.isNotEmpty)  params['nis']     = nis;
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return url; // fallback: tetap pakai URL asli jika parsing gagal
    }
  }

  void _showError(String title, String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: context.rs(15),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: context.rs(13)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Tutup',
              style: GoogleFonts.poppins(fontSize: context.rs(13)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: CustomScrollView(
        // BouncingScrollPhysics terasa native di iOS & smooth di Android
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            // Gunakan horizontalPadding: lebih lebar di tablet
            padding: EdgeInsets.symmetric(
              horizontal: context.horizontalPadding,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(height: context.rs(20)),
                // MaxWidthBox: batasi lebar konten di tablet
                MaxWidthBox(child: _buildConnectionBanner()),
                SizedBox(height: context.rs(20)),
                MaxWidthBox(child: _buildScanCard()),
                SizedBox(height: context.rs(12)),
                MaxWidthBox(child: _buildGeneratorCard()),
                if (_history.isNotEmpty) ...[
                  SizedBox(height: context.rs(28)),
                  MaxWidthBox(child: _buildHistorySection()),
                ],
                SizedBox(height: context.rs(28)),
                MaxWidthBox(child: _buildGuide()),
                SizedBox(height: context.rs(48)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sliver App Bar ─────────────────────────────────────────────
  Widget _buildSliverAppBar() {
    // Tablet: expandedHeight sedikit lebih besar
    final expandedHeight = context.isTablet
        ? context.rs(200.0)
        : context.rs(170.0);

    return SliverAppBar(
      expandedHeight: expandedHeight,
      collapsedHeight: kToolbarHeight,
      pinned: true,
      stretch: true,
      backgroundColor: const Color(0xFF1B5E20),
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final minH = kToolbarHeight + MediaQuery.of(context).padding.top;
          final maxH = expandedHeight + MediaQuery.of(context).padding.top;
          final collapseRatio = ((maxH - constraints.maxHeight) / (maxH - minH))
              .clamp(0.0, 1.0);
          final expandRatio = 1.0 - collapseRatio;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Gradient background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1B5E20),
                      AppColors.primaryGreen,
                      Color(0xFF81C784),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              // Dekoratif lingkaran
              Positioned(
                top: -50 * expandRatio,
                right: -40,
                child: Opacity(
                  opacity: expandRatio * 0.9,
                  child: Container(
                    width: context.isTablet ? 280 : 200,
                    height: context.isTablet ? 280 : 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -30,
                child: Opacity(
                  opacity: expandRatio * 0.8,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 30 * expandRatio + 12,
                child: Opacity(
                  opacity: expandRatio * 0.25,
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: CustomPaint(painter: _DotGridPainter()),
                  ),
                ),
              ),

              // EXPANDED content
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: expandRatio.clamp(0.0, 1.0),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.rs(20),
                        0,
                        context.rs(20),
                        context.rs(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: () {
                              _logoTapCount++;
                              final remaining = 7 - _logoTapCount;
                              if (_logoTapCount >= 7) {
                                _logoTapCount = 0;
                                openTeacherMode(context);
                              } else if (remaining <= 3) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '$remaining lagi untuk mode guru',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    margin: EdgeInsets.fromLTRB(
                                      context.rs(16), 0, context.rs(16), context.rs(80),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.all(context.rs(11)),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.school,
                                color: Colors.white,
                                size: context.rs(28),
                              ),
                            ),
                          ),
                          SizedBox(width: context.rs(14)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppConfig.appName,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: context.rs(26),
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Text(
                                  'Secure Exam Browser',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withOpacity(0.72),
                                    fontSize: context.rs(11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.rs(10),
                              vertical: context.rs(5),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.28),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'v${AppConfig.appVersion}',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: context.rs(10),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // COLLAPSED content
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: 0,
                child: Opacity(
                  opacity: collapseRatio.clamp(0.0, 1.0),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: context.rs(16)),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.school,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            AppConfig.appName,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _connected
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _connected
                                        ? const Color(0xFFA5D6A7)
                                        : Colors.orange.shade300,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _connected ? 'Online' : 'Offline',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Connection Banner ──────────────────────────────────────────
  Widget _buildConnectionBanner() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.25),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: _connected ? _connectedBanner() : _disconnectedBanner(),
    );
  }

  Widget _connectedBanner() {
    return Container(
      key: const ValueKey('on'),
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(16),
        vertical: context.rs(12),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_rounded,
              color: AppColors.primaryGreen,
              size: 17,
            ),
          ),
          SizedBox(width: context.rs(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Internet Terhubung',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryGreen,
                    fontSize: context.rs(13),
                  ),
                ),
                Text(
                  'Siap memulai ujian',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(11),
                    color: AppColors.primaryGreen.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.rs(10),
              vertical: context.rs(4),
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Online',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: context.rs(10),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _disconnectedBanner() {
    return Container(
      key: const ValueKey('off'),
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(16),
        vertical: context.rs(14),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: Colors.orange,
              size: 17,
            ),
          ),
          SizedBox(width: context.rs(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tidak Ada Koneksi',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800,
                    fontSize: context.rs(13),
                  ),
                ),
                Text(
                  'Menunggu koneksi internet…',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(11),
                    color: Colors.orange.shade600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.orange.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Scan Card ─────────────────────────────────────────────────
  Widget _buildScanCard() {
    return ScaleTransition(
      scale: _connected ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
      child: GestureDetector(
        onTap: _connected ? _onScanTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: EdgeInsets.all(context.rs(22)),
          decoration: BoxDecoration(
            gradient: _connected
                ? const LinearGradient(
                    colors: [Color(0xFF2E7D32), AppColors.primaryGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade400, Colors.grey.shade500],
                  ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: _connected
                ? [
                    BoxShadow(
                      color: AppColors.primaryGreen.withOpacity(0.38),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(14)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: context.rs(30),
                ),
              ),
              SizedBox(width: context.rs(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pindai QR Ujian',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: context.rs(17),
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: context.rs(3)),
                    Text(
                      _connected
                          ? 'Ketuk untuk mulai scan'
                          : 'Butuh koneksi internet',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: context.rs(11),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(context.rs(8)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: context.rs(14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Generator Card ─────────────────────────────────────────────
  Widget _buildGeneratorCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QRGeneratorScreen()),
      ),
      child: Container(
        padding: EdgeInsets.all(context.rs(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primaryGreen.withOpacity(0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(context.rs(10)),
              decoration: BoxDecoration(
                color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.qr_code_2,
                color: AppColors.primaryGreen,
                size: 22,
              ),
            ),
            SizedBox(width: context.rs(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Buat QR Ujian',
                    style: GoogleFonts.poppins(
                      fontSize: context.rs(14),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Khusus pengawas / guru',
                    style: GoogleFonts.poppins(
                      fontSize: context.rs(11),
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(11),
                vertical: context.rs(5),
              ),
              decoration: BoxDecoration(
                color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Generator',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(11),
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── History Section ────────────────────────────────────────────
  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: context.rs(8)),
            Text(
              'Riwayat Terakhir',
              style: GoogleFonts.poppins(
                fontSize: context.rs(15),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _clearHistory,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(11),
                  vertical: context.rs(5),
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Hapus Semua',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(11),
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: context.rs(14)),
        ..._history.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Padding(
            padding: EdgeInsets.only(bottom: context.rs(10)),
            child: GestureDetector(
              onTap: () => _confirmAndStart(item.url, title: item.title),
              child: Container(
                padding: EdgeInsets.all(context.rs(14)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: context.rs(36),
                      height: context.rs(36),
                      decoration: BoxDecoration(
                        color: i == 0
                            ? AppColors.primaryGreen
                            : AppColors.paleGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: i == 0
                            ? const Icon(
                                Icons.history_edu,
                                color: Colors.white,
                                size: 16,
                              )
                            : Text(
                                '${i + 1}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(width: context.rs(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayLabel,
                            style: GoogleFonts.poppins(
                              fontSize: context.rs(13),
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.url,
                            style: GoogleFonts.poppins(
                              fontSize: context.rs(10),
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: context.rs(8)),
                    Container(
                      padding: EdgeInsets.all(context.rs(8)),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AppColors.primaryGreen,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Guide Section ──────────────────────────────────────────────
  Widget _buildGuide() {
    final steps = [
      (Icons.wifi_rounded, 'Pastikan koneksi internet stabil'),
      (Icons.qr_code_2, 'Pengawas buat QR via tombol "Buat QR Ujian"'),
      (Icons.qr_code_scanner, 'Peserta scan QR menggunakan tombol "Pindai"'),
      (Icons.edit_note_rounded, 'Kerjakan ujian dengan jujur'),
      (
        Icons.logout_rounded,
        'Tekan "Keluar" ${AppConfig.exitPressRequired}× untuk mengakhiri',
      ),
    ];

    return Container(
      padding: EdgeInsets.all(context.rs(20)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: context.rs(8)),
              Text(
                'Cara Menggunakan',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: context.rs(15),
                ),
              ),
            ],
          ),
          SizedBox(height: context.rs(18)),
          ...steps.asMap().entries.map((entry) {
            final i = entry.key;
            final step = entry.value;
            final isLast = i == steps.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: context.rs(34),
                      height: context.rs(34),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          step.$1,
                          color: AppColors.primaryGreen,
                          size: context.rs(16),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: context.rs(28),
                        color: AppColors.primaryGreen.withOpacity(0.12),
                      ),
                  ],
                ),
                SizedBox(width: context.rs(12)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: context.rs(7),
                      bottom: isLast ? 0 : context.rs(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: context.rs(18),
                          height: context.rs(18),
                          margin: EdgeInsets.only(right: context.rs(8)),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: GoogleFonts.poppins(
                                fontSize: context.rs(9),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            step.$2,
                            style: GoogleFonts.poppins(
                              fontSize: context.rs(12),
                              color: AppColors.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Dot grid ─────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 14.0;
    const radius = 1.8;
    final paint = Paint()..color = Colors.white;
    for (double x = 0; x <= size.width; x += spacing) {
      for (double y = 0; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
