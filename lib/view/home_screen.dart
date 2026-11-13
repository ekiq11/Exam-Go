import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/models/tryout_schedule_model.dart';
import 'package:examgo/models/exam_question_model.dart';
import 'package:examgo/services/exam_cache_service.dart';
import 'package:examgo/services/student_tryout_history_service.dart';
import 'package:examgo/services/trusted_time_service.dart';
import 'package:examgo/services/tryout_reminder_service.dart';
import 'package:examgo/view/student/event_dashboard_screen.dart';
import 'package:examgo/view/student/tryout_discussion_screen.dart';
import 'package:examgo/view/student/widgets/exam_time_lock_dialog.dart';
import 'package:examgo/view/widgets/premium_token_dialog.dart';
import 'package:examgo/view/student/tryout_schedule_screen.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/app_remote_config.dart';
import '../services/popup_ad_service.dart';
import 'widgets/popup_ad_dialog.dart';
import 'widgets/examgo_dialog.dart';
import 'widgets/examgo_loading_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:examgo/services/license_service.dart';
import 'package:examgo/services/exam_session_service.dart';
import 'package:examgo/services/monitoring_service.dart';
import '../constant/security_service.dart';
import 'package:examgo/view/pre_exam_checklist.dart';
import 'package:examgo/view/qr_scanner.dart';
import 'package:examgo/view/qris_web_view.dart';
import 'package:examgo/view/teacher_mode.dart';
import 'package:examgo/view/student/student_exam_session_screen.dart';
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
  final String examId;
  const _HistoryItem({
    required this.title,
    required this.url,
    this.examId = '',
  });

  String toStorage() => '$title\x00$url\x00$examId';

  static _HistoryItem fromStorage(String raw) {
    final parts = raw.split('\x00');
    if (parts.length >= 2) {
      return _HistoryItem(
        title: parts[0],
        url: parts[1],
        examId: parts.length > 2 ? parts[2] : '',
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
  bool _isStudentPremium = false;
  Map<String, dynamic> _tryoutCardData = {'isPremium': false, 'newCount': 0};

  static const _historyKey = 'scan_history_v3';
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Bersihkan seluruh kiosk / lock dari sesi sebelumnya saat berada di Home
    SecurityService.instance.emergencyReset();

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
    _refreshPremiumAndStatus();
    // Cek apakah ada sesi ujian yang tidak selesai (crash recovery)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForceUpdate().then((_) {
        _checkCrashRecovery().then((_) {
          _checkPopupAd();
          TryoutReminderService.instance.checkAndSendLocalReminder();
        });
      });
    });
    // FIX BUG-07: Clock dikelola oleh _ClockWidget — tidak perlu timer di sini.
  }

  Future<void> _refreshPremiumAndStatus() async {
    try {
      final isPrem = await LicenseService.instance.isStudentPremium();
      int newCount = 0;
      if (isPrem) {
        newCount = await TryoutReminderService.instance.getNewUnattemptedCount();
      }
      if (mounted) {
        setState(() {
          _isStudentPremium = isPrem;
          _tryoutCardData = {'isPremium': isPrem, 'newCount': newCount};
        });
      }
    } catch (_) {}
  }

  static bool _hasShownAppLaunchAd = false;

  /// Cek dan tampilkan popup iklan Lynk.id (1:1) saat aplikasi dibuka
  Future<void> _checkPopupAd() async {
    if (_hasShownAppLaunchAd) return;
    _hasShownAppLaunchAd = true;

    try {
      final isStudentPremium = await LicenseService.instance.isStudentPremium();
      final isTeacherPremium = await LicenseService.instance.isTeacherPremium();
      final isPremium = isStudentPremium || isTeacherPremium;
      final config = await PopupAdService.instance.getAdsConfig();

      if (!mounted) return;

      // 1. Iklan EVENT: Prioritas tertinggi, tampil untuk semua user (Free maupun Premium)
      if (config.event.isValid) {
        PopupAdDialog.show(
          context,
          ad: config.event,
          roleBadge: 'EVENT SPESIAL',
        );
        return;
      }

      // 2. Iklan SISWA: Tampil HANYA jika akun masih FREE
      //    Jika sudah Premium, iklan siswa disembunyikan otomatis
      if (!isPremium && config.student.isValid) {
        PopupAdDialog.show(
          context,
          ad: config.student,
          roleBadge: 'PROMO SISWA',
        );
      }
    } catch (_) {}
  }

  Future<void> _checkForceUpdate() async {
    // Tunggu Remote Config ready
    await AppRemoteConfig.instance.init();
    if (AppConfig.appBuildNumber < AppRemoteConfig.instance.minAppBuild) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Update Tersedia',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              'Versi aplikasi ExamGO Anda sudah usang dan memiliki celah keamanan.\n\nHarap perbarui aplikasi Anda ke versi terbaru untuk melanjutkan ujian.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  // Arahkan ke Play Store / URL Download sekolah (Bisa diganti URL aktual)
                  // launchUrl(Uri.parse('market://details?id=com.examgo.app'));
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: Text(
                  'Update Sekarang',
                  style: GoogleFonts.poppins(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    // FIX CRASH-1: StandardMethodCodec.decodeEnvelope crash (312 events, 224 users).
    // connectivity_plus pakai EventChannel di bawahnya. Saat dispose() dipanggil
    // sebelum EventChannel stream fully connected (race condition saat navigasi cepat
    // atau hot-restart), native side melempar "No active stream to cancel" sebagai
    // PlatformException yang TIDAK bisa ditangkap oleh .catchError() karena
    // exception-nya dilempar secara sinkron dari StandardMethodCodec.decodeEnvelope.
    //
    // Fix: wrap seluruh cancel() dalam try/catch sinkron, lalu juga .catchError()
    // sebagai double-guard untuk error async yang mungkin datang belakangan.
    try {
      _connectSub?.cancel().catchError((_) {});
    } catch (_) {
      // Intentionally ignored — "No active stream to cancel" bukan kondisi fatal.
    }
    _connectSub = null;
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

  void _showDeviceBlockedPopup() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.phonelink_lock_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(
              'Perangkat Ditolak',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Nomor NIS Anda sudah terdaftar dan masuk ujian menggunakan perangkat (HP) lain.\n\nSistem ExamGO mencegah login ganda untuk menghindari perjokian. Hubungi pengawas untuk mereset perangkat Anda.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              'Tutup',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Teacher Mode Request ───────────────────────────────────────────

  Future<void> _checkCrashRecovery() async {
    final session = await ExamSessionService.instance.getActiveSession();
    if (session == null || !mounted) return;

    final resume = await ExamGoDialog.confirm(
      context,
      title: 'Lanjutkan Sesi Ujian?',
      message:
          'Ujian "${session.title}" belum diselesaikan. Ingin melanjutkan kembali ke ruang ujian?',
      confirmText: 'Lanjutkan',
      cancelText: 'Abaikan',
      icon: Icons.restore_rounded,
      iconColor: const Color(0xFFD97706),
      iconBgColor: const Color(0xFFFEF3C7),
    );

    if (resume != true || !mounted) {
      await ExamSessionService.instance.clear();
      return;
    }

    // Cek apakah siswa masih diblokir oleh pengawas atau pindah device
    if (session.examId.isNotEmpty && session.studentNis.isNotEmpty) {
      final studentData = await MonitoringService.instance.getStudentData(
        session.examId,
        session.studentNis,
      );
      if (studentData != null) {
        if (studentData['status'] == 'BLOCKED') {
          if (mounted) _showViolationPopup();
          return;
        }
        final currentDeviceId = await MonitoringService.instance.getDeviceId();
        if (studentData['device_id'] != null &&
            studentData['device_id'] != currentDeviceId) {
          if (mounted) _showDeviceBlockedPopup();
          return;
        }
      }
    }

    // Langsung buka WebView dengan URL dari sesi sebelumnya
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamWebViewScreen(
          url: session.url,
          title: session.title,
          examId: session.examId,
          studentName: session.studentName,
          studentNis: session.studentNis,
        ),
      ),
    );

    if (result == 'blocked_violation' && mounted) {
      _showViolationPopup();
    }
  }

  // ─── History ──────────────────────────────────────────────────

  Future<String> _getHistoryKey() async {
    try {
      final deviceId = await LicenseService.instance.getDeviceId();
      final cleanId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      return 'scan_history_v3_$cleanId';
    } catch (_) {
      return _historyKey;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getHistoryKey();
      var saved = prefs.getStringList(key);
      if (saved == null) {
        // Migrasi data lama dari key global jika ada
        saved = prefs.getStringList(_historyKey);
        if (saved != null && saved.isNotEmpty) {
          await prefs.setStringList(key, saved);
        }
      }
      if (!mounted) return;
      setState(() => _history = (saved ?? []).map(_HistoryItem.fromStorage).toList());
    } catch (_) {}
  }

  Future<void> _saveEntry(_HistoryItem item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getHistoryKey();
      final current = prefs.getStringList(key) ?? [];
      final dedup = current
          .where((e) => _HistoryItem.fromStorage(e).url != item.url)
          .toList();
      final updated = [
        item.toStorage(),
        ...dedup,
      ].take(AppConfig.maxScanHistory).toList();
      await prefs.setStringList(key, updated);
      if (!mounted) return;
      setState(() => _history = updated.map(_HistoryItem.fromStorage).toList());
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    final confirm = await ExamGoDialog.danger(
      context,
      title: 'Hapus Riwayat Scan?',
      message: 'Semua riwayat scan QR ujian akan dihapus dari perangkat.',
      confirmText: 'Hapus',
    );
    if (confirm != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getHistoryKey();
      await prefs.remove(key);
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
    await _saveEntry(
      _HistoryItem(title: result.title, url: result.url, examId: result.examId),
    );
    _confirmAndStart(result.url, title: result.title, examId: result.examId);
  }

  Future<void> _confirmAndStart(
    String url, {
    String title = '',
    String examId = '',
  }) async {
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
    final nis = identity['nis'] ?? '';

    final prepLoading = ExamGoLoadingDialog.show(
      context,
      title: 'Menyiapkan Lembar Ujian...',
      message: 'Memeriksa status peserta & menyiapkan lembar soal...',
    );

    // ── A. Sisipkan identitas ke URL ujian sebagai query parameter ──
    // Server ujian (Google Form / LMS) akan menerima ?peserta=Budi&nis=12345
    // sehingga rekap jawaban otomatis mencatat nama peserta.
    final finalUrl = _appendIdentityToUrl(url, name: name, nis: nis);

    // ── B. Set Firebase Analytics user properties ──────────────────
    // Guru yang punya akses Firebase Console bisa melihat per-user.
    // Juga berguna jika terjadi crash — Crashlytics tahu siapa yang crash.
    AnalyticsService.instance.setStudentIdentity(name: name, nis: nis);

    // Cek apakah siswa masih diblokir oleh pengawas
    if (examId.isNotEmpty && nis.isNotEmpty) {
      final studentData = await MonitoringService.instance.getStudentData(
        examId,
        nis,
      );
      if (studentData != null) {
        if (studentData['status'] == 'BLOCKED') {
          prepLoading.dismiss();
          if (mounted) _showViolationPopup();
          return;
        }
        final currentDeviceId = await MonitoringService.instance.getDeviceId();
        if (studentData['device_id'] != null &&
            studentData['device_id'] != currentDeviceId) {
          prepLoading.dismiss();
          if (mounted) _showDeviceBlockedPopup();
          return;
        }
      }
    }

    // ── Catat Penggunaan Ujian Siswa (Akses Ujian Dasar Bebas Kuota / Unlimited) ──
    final isEventExam = url.startsWith('EXAMGO_EVENT://');
    if (!isEventExam) {
      await LicenseService.instance.recordExamAttempt();
      if (mounted) setState(() {});
    }

    // Cek apakah ini ujian native ExamGO Tryout (Docx/GForm) atau Event
    final isNative =
        url.startsWith('EXAMGO_TRYOUT://') ||
        url.startsWith('EXAMGO_EVENT://') ||
        examId.isNotEmpty;
    final token = url.startsWith('EXAMGO_EVENT://')
        ? url.replaceFirst('EXAMGO_EVENT://', '')
        : (url.startsWith('EXAMGO_TRYOUT://')
              ? url.replaceFirst('EXAMGO_TRYOUT://', '')
              : examId);

    if (isNative && token.isNotEmpty) {
      try {
        final tokenUpper = token.trim().toUpperCase();
        var pkgDoc = await FirebaseFirestore.instance
            .collection('paket_tryout')
            .doc(tokenUpper)
            .get();
        if (!pkgDoc.exists && tokenUpper != token.trim()) {
          pkgDoc = await FirebaseFirestore.instance
              .collection('paket_tryout')
              .doc(token.trim())
              .get();
        }
        if (pkgDoc.exists) {
          final pkgData = pkgDoc.data() ?? {};
          final isTeacherGen =
              pkgData['is_teacher_generated'] == true ||
              pkgData['allow_retake'] == false ||
              pkgData['guru_id'] != null ||
              pkgData['creator_id'] != null;

          // ── Cek Pembatasan 1 Device / 1 Kali Pengerjaan (Soal Buatan Guru) ──
          if (isTeacherGen) {
            final history = await StudentTryoutHistoryService.instance
                .getHistory();
            final existingAttempt = history
                .where((h) => h.token.trim().toUpperCase() == tokenUpper)
                .firstOrNull;

            // Cek apakah guru sudah memberikan izin ujian ulang di server
            bool retakePermitted = false;
            if (nis.isNotEmpty) {
              final sData = await MonitoringService.instance.getStudentData(
                tokenUpper,
                nis,
              );
              if (sData != null && sData['allow_retake'] == true) {
                retakePermitted = true;
              } else {
                final prefs = await SharedPreferences.getInstance();
                retakePermitted = prefs.getBool('retake_allowed_${tokenUpper}_$nis') ?? false;
              }
            }

            // Jika sudah pernah mengerjakan dan belum diizinkan ulang oleh guru -> Alihkan ke Pembahasan jika waktu sudah habis
            if (existingAttempt != null && !retakePermitted) {
              if (!mounted) return;

              // Hitung apakah waktu ujian resmi masih berjalan
              DateTime? effectiveEndTime = existingAttempt.examEndTime;
              if (effectiveEndTime == null && pkgData['durasi_menit'] != null) {
                final durasi = (pkgData['durasi_menit'] as num).toInt();
                effectiveEndTime = existingAttempt.submittedAt.add(
                  Duration(minutes: durasi),
                );
              }

              // Verifikasi anti-cheat jam HP manual via TrustedTimeService
              final isTimeEnded = await TrustedTimeService.instance
                  .isExamTimeEnded(
                    examEndTime: effectiveEndTime,
                    submittedAt: existingAttempt.submittedAt,
                    elapsedRealtimeMs: existingAttempt.elapsedRealtimeMs,
                  );

              // Jika waktu ujian belum habis, kunci akses pembahasan demi integritas ujian
              if (!isTimeEnded && effectiveEndTime != null) {
                prepLoading.dismiss();
                if (!mounted) return;
                await showExamTimeLockDialog(
                  context,
                  endTime: effectiveEndTime,
                  examTitle: existingAttempt.namaPaket.isNotEmpty
                      ? existingAttempt.namaPaket
                      : (pkgData['nama_paket'] ?? 'Ujian'),
                );
                return;
              }

              // Jika waktu ujian sudah berakhir -> Alihkan ke Pembahasan & Kunci
              if (!mounted) {
                prepLoading.dismiss();
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Waktu ujian telah berakhir. Mengalihkan ke Halaman Pembahasan & Kunci...',
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                  backgroundColor: const Color(0xFF0F172A),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );

              // Ambil butir soal dari cache atau unduh jika belum lengkap
              prepLoading.update(message: 'Menyiapkan pembahasan & kunci jawaban...');
              List<ExamQuestion> questions = existingAttempt.questions;
              if (questions.isEmpty) {
                final cached = await ExamCacheService.instance.loadExam(
                  tokenUpper,
                );
                if (cached != null && cached.questions.isNotEmpty) {
                  questions = cached.questions;
                } else {
                  final downloaded = await ExamCacheService.instance
                      .downloadAndCacheExam(paketId: tokenUpper);
                  questions = downloaded.questions;
                }
              }

              prepLoading.dismiss();
              if (mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TryoutDiscussionScreen(
                      title: existingAttempt.namaPaket.isNotEmpty
                          ? existingAttempt.namaPaket
                          : (pkgData['nama_paket'] ?? 'Pembahasan Ujian'),
                      kategori: existingAttempt.kategori.isNotEmpty
                          ? existingAttempt.kategori
                          : (pkgData['kategori'] ?? 'CBT Guru'),
                      questions: questions,
                      studentAnswers: existingAttempt.jawaban,
                      score: existingAttempt.finalScore,
                      statusKelulusan: existingAttempt.statusKelulusan,
                      returnToHome: true,
                      token: tokenUpper,
                    ),
                  ),
                );
              }
              if (mounted) setState(() {});
              return;
            }
          }

          prepLoading.dismiss();
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentExamSessionScreen(
                token: tokenUpper,
                studentName: name,
                studentNis: nis,
                isEvent: isEventExam,
                initialSchedule: TryoutSchedule.fromMap(
                  pkgDoc.id,
                  pkgDoc.data() ?? {},
                ),
                returnToHome: true,
              ),
            ),
          );
          if (mounted) setState(() {});
          return;
        }
      } catch (_) {
        prepLoading.dismiss();
      }
    }

    prepLoading.dismiss();
    // Arahkan ke WebView dengan URL yang sudah mengandung identitas
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamWebViewScreen(
          url: finalUrl,
          title: displayTitle,
          examId: examId,
          studentName: name,
          studentNis: nis,
        ),
      ),
    );

    if (mounted) setState(() {});

    if (result == 'blocked_violation' && mounted) {
      _showViolationPopup();
    }
  }

  // ─── Lisensi & Kuota Freemium Siswa (Lynk.id) ─────────────────

  Widget _buildLicenseQuotaBadge() {
    final isPremium = _isStudentPremium;

        if (isPremium) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD97706).withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFFB45309),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '👑 SISWA PREMIUM LIFETIME',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF92400E),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Akses bebas ujian & paket tryout selamanya',
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          color: const Color(0xFFB45309),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 13,
                          color: Color(0xFF059669),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'AKUN SISWA AKTIF',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF065F46),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.all_inclusive_rounded,
                        size: 15,
                        color: Color(0xFF059669),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ujian Gratis Tanpa Batas',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bebas ujian sekolah & QR. Buka akses Tryout SNBT, Pembahasan, & Sertifikat dengan Lynk.id.',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _showStudentLicenseDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Upgrade 👑',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
  }

  void _showStudentLicenseDialog() {
    PremiumTokenDialog.show(
      context,
      userType: 'STUDENT_LIFETIME',
      onActivated: () {
        _refreshPremiumAndStatus();
        if (mounted) setState(() {});
      },
    );
  }

  void _showAccountPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.primaryGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Akun & Privasi Data',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Kepatuhan Standar Google Play & App Store',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FutureBuilder<bool>(
              future: LicenseService.instance.isStudentPremium(),
              builder: (ctx, snap) {
                final isPrem = snap.data ?? false;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPrem
                            ? Icons.workspace_premium_rounded
                            : Icons.person_outline_rounded,
                        color: isPrem
                            ? const Color(0xFFD97706)
                            : AppColors.primaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isPrem
                            ? 'Status: Siswa Premium Lifetime'
                            : 'Status: Akun Siswa Reguler',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Tautan Kebijakan Privasi (Wajib untuk Google Play & Apple App Store)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final uri = Uri.parse('https://examgo.id/privacy');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.privacy_tip_outlined,
                        color: Color(0xFF475569),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kebijakan Privasi (Privacy Policy)',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              'Lihat transparansi perlindungan & pemrosesan data',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: Color(0xFF64748B),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirmed = await ExamGoDialog.danger(
                    context,
                    title: 'Hapus Akun & Data Perangkat?',
                    message:
                        'Seluruh data lokal, token lisensi aktif, riwayat pengerjaan tryout, dan cache soal pada perangkat ini akan dihapus permanen sesuai standar privasi data Apple & Google. Tindakan ini tidak dapat dibatalkan.',
                    confirmText: 'Hapus Permanen',
                  );

                  if (confirmed == true) {
                    await LicenseService.instance.clearAllUserAccountData();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Seluruh data akun dan riwayat berhasil dibersihkan.',
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                        backgroundColor: const Color(0xFF0F172A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _history.clear();
                        _isStudentPremium = false;
                        _tryoutCardData = {'isPremium': false, 'newCount': 0};
                      });
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_forever_rounded,
                        color: Color(0xFFDC2626),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hapus Akun & Riwayat Ujian',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                            Text(
                              'Bersihkan semua data lokal & reset app ke awal',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                color: const Color(0xFF991B1B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTryoutCard() {
    final isPremium = _tryoutCardData['isPremium'] as bool? ?? false;
    final newCount = _tryoutCardData['newCount'] as int? ?? 0;

    return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            if (isPremium) {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TryoutScheduleScreen()),
              );
              if (mounted) setState(() {});
            } else {
              _showStudentLicenseDialog();
            }
          },
          child: Container(
            padding: EdgeInsets.all(context.rs(16)),
            decoration: BoxDecoration(
              gradient: isPremium
                  ? const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isPremium ? null : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPremium
                    ? Colors.transparent
                    : const Color(0xFFD97706).withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPremium
                      ? const Color(0xFF0D9488).withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.04),
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
                    color: isPremium
                        ? Colors.white.withValues(alpha: 0.2)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: isPremium ? Colors.white : const Color(0xFFD97706),
                    size: context.rs(28),
                  ),
                ),
                SizedBox(width: context.rs(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Paket Tryout',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: context.rs(14),
                                fontWeight: FontWeight.bold,
                                color: isPremium
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isPremium
                                  ? const Color(
                                      0xFFFBBF24,
                                    ).withValues(alpha: 0.25)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isPremium ? 'PREMIUM' : 'LOCKED',
                              style: GoogleFonts.poppins(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isPremium
                                    ? const Color(0xFFFDE68A)
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                          if (newCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFEF4444),
                                    Color(0xFFF97316),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFEF4444,
                                    ).withValues(alpha: 0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.bolt_rounded,
                                    size: 10.5,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    newCount == 1 ? '1 BARU' : '$newCount BARU',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: context.rs(3)),
                      Text(
                        isPremium
                            ? 'Akses bank soal resmi SNBT, SKD, & TKA terjadwal'
                            : 'Khusus Siswa Premium. Beli token untuk membuka.',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(11.5),
                          color: isPremium
                              ? Colors.white.withValues(alpha: 0.85)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isPremium
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.lock_rounded,
                  size: context.rs(18),
                  color: isPremium
                      ? Colors.white.withValues(alpha: 0.7)
                      : const Color(0xFFD97706),
                ),
              ],
            ),
          ),
        );
  }

  void _showViolationPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.red.shade900.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.gpp_bad_rounded,
                  color: Colors.red.shade600,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Akses Diblokir',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Ujian Anda dibatalkan karena terdeteksi melakukan pelanggaran maksimal (seperti meminimize atau membuka aplikasi lain) selama ujian berlangsung.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Silakan lapor kepada pengawas ujian untuk meminta pembukaan akses blokir.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Saya Mengerti',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menambahkan query parameter peserta & nis ke URL ujian.
  /// Jika URL sudah punya query, parameter ditambahkan (tidak menimpa).
  String _appendIdentityToUrl(
    String url, {
    required String name,
    required String nis,
  }) {
    try {
      if (name.isEmpty && nis.isEmpty) return url;
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);
      if (name.isNotEmpty) params['peserta'] = name;
      if (nis.isNotEmpty) params['nis'] = nis;
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return url; // fallback: tetap pakai URL asli jika parsing gagal
    }
  }

  void _showError(String title, String msg) {
    if (!mounted) return;
    ExamGoDialog.info(
      context,
      title: title,
      message: msg,
      buttonText: 'Tutup',
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFDC2626),
      iconBgColor: const Color(0xFFFEE2E2),
    );
  }

  // FIX BUG-07+08: _formatDateTime dipindahkan ke _ClockWidget
  // sehingga hanya clock text yang rebuild setiap detik, bukan seluruh HomeScreen.

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: CustomScrollView(
        // AlwaysScrollableScrollPhysics konsisten dan mencegah layar bergetar saat scroll
        physics: const AlwaysScrollableScrollPhysics(),
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
                MaxWidthBox(child: _buildLicenseQuotaBadge()),
                SizedBox(height: context.rs(14)),
                MaxWidthBox(child: _buildScanCard()),
                SizedBox(height: context.rs(12)),
                MaxWidthBox(child: _buildInputTokenCard()),
                SizedBox(height: context.rs(12)),
                MaxWidthBox(child: _buildGeneratorCard()),
                SizedBox(height: context.rs(12)),
                MaxWidthBox(child: _buildTryoutCard()),

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
      pinned: true,
      backgroundColor: const Color(0xFF1B5E20),
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final minH = kToolbarHeight + MediaQuery.of(context).padding.top;
          final maxH = expandedHeight + MediaQuery.of(context).padding.top;
          final collapseRatio = ((maxH - constraints.maxHeight) / (maxH - minH))
              .clamp(0.0, 1.0);
          final expandRatio = (1.0 - collapseRatio).clamp(0.0, 1.0);

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
                      color: Colors.white.withValues(alpha: 0.08),
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
                      color: Colors.white.withValues(alpha: 0.05),
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
                child: IgnorePointer(
                  ignoring: expandRatio < 0.25,
                  child: Opacity(
                    opacity: expandRatio,
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
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                        ),
                                      ),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      margin: EdgeInsets.fromLTRB(
                                        context.rs(16),
                                        0,
                                        context.rs(16),
                                        context.rs(80),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.all(context.rs(11)),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
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
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  SizedBox(height: context.rs(2)),
                                  Text(
                                    'Secure Exam Browser',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: context.rs(11),
                                    ),
                                  ),
                                  SizedBox(height: context.rs(8)),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: context.rs(8),
                                      vertical: context.rs(4),
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    // FIX BUG-07: Gunakan _ClockWidget — hanya rebuild text jam,
                                    // bukan seluruh HomeScreen setiap detik.
                                    child: const _ClockWidget(),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showAccountPrivacySheet(context),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: context.rs(9),
                                  vertical: context.rs(5),
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.28),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.shield_outlined,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                    SizedBox(width: context.rs(4)),
                                    Text(
                                      'v${AppConfig.appVersion}',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: context.rs(10),
                                        fontWeight: FontWeight.w600,
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
                  ),
                ),
              ),

              // COLLAPSED content
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: collapseRatio < 0.75,
                  child: Opacity(
                    opacity: collapseRatio,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
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
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.3),
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
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _showAccountPrivacySheet(context),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shield_outlined,
                                  color: Colors.white,
                                  size: 16,
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
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.12),
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
                    color: AppColors.primaryGreen.withValues(alpha: 0.65),
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
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
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
                      color: AppColors.primaryGreen.withValues(alpha: 0.38),
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
                  color: Colors.white.withValues(alpha: 0.2),
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
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: context.rs(3)),
                    Text(
                      _connected
                          ? 'Ketuk untuk mulai scan'
                          : 'Butuh koneksi internet',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: context.rs(11),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(context.rs(8)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
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

  Future<Map<String, String>?> _promptUserProfileIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('student_name') ?? '';
    String email = prefs.getString('student_email') ?? '';
    String wa = prefs.getString('student_whatsapp') ?? '';

    if (name.isNotEmpty && email.isNotEmpty && wa.isNotEmpty) {
      return {'name': name, 'email': email, 'whatsapp': wa};
    }

    if (!mounted) return null;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StudentProfileDialog(
        initialName: name,
        initialEmail: email,
        initialWa: wa,
      ),
    );

    if (confirmed == true) {
      final reloadedPrefs = await SharedPreferences.getInstance();
      return {
        'name': reloadedPrefs.getString('student_name') ?? '',
        'email': reloadedPrefs.getString('student_email') ?? '',
        'whatsapp': reloadedPrefs.getString('student_whatsapp') ?? '',
      };
    }
    return null;
  }

  Widget _buildInputTokenCard() {
    return GestureDetector(
      onTap: () async {
        if (!_connected) {
          _showError(
            'Tidak Ada Koneksi',
            'Pastikan perangkat terhubung ke internet sebelum ujian.',
          );
          return;
        }

        final token = await showDialog<String>(
          context: context,
          builder: (ctx) => const ManualTokenInputDialog(),
        );

        if (token == null || token.isEmpty || !mounted) return;

        // Tampilkan loading indikator pencarian token profesional & terpadu
        final searchLoading = ExamGoLoadingDialog.show(
          context,
          title: 'Mencari Token Ujian...',
          message: 'Menghubungkan ke server CBT & memeriksa sesi...',
        );

        try {
          // 1. Cek sesi ujian guru
          try {
            final doc = await FirebaseFirestore.instance
                .collection('exam_sessions')
                .doc(token)
                .get();
            if (doc.exists) {
              searchLoading.dismiss();
              final data = doc.data()!;
              final title = data['title'] ?? 'Ujian';
              final url = data['url'] ?? '';
              // Tandai sesi terisi siswa secara atomic (student_count increment, hemat kuota)
              doc.reference
                  .update({
                    'student_count': FieldValue.increment(1),
                    'last_joined_at': FieldValue.serverTimestamp(),
                  })
                  .catchError((_) {});
              await _saveEntry(
                _HistoryItem(title: title, url: url, examId: token),
              );
              _confirmAndStart(url, title: title, examId: token);
              return;
            }
          } catch (_) {}

          // 2. Fallback 1: Cek dokumen paket_tryout native (Tryout / Ujian Khusus / Event)
          try {
            searchLoading.update(
              title: 'Mencari Paket Soal...',
              message: 'Memeriksa bank soal tryout & jadwal event...',
            );
            final pkgDoc = await FirebaseFirestore.instance
                .collection('paket_tryout')
                .doc(token)
                .get();
            if (pkgDoc.exists) {
              searchLoading.dismiss();
              final pData = pkgDoc.data() ?? {};
              final title = pData['nama_paket'] ?? 'Tryout';
              final isEventPkg =
                  pData['jenis_test']?.toString().toUpperCase() == 'EVENT' ||
                  pData['is_event'] == true ||
                  token.startsWith('EVENT');

              if (isEventPkg) {
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDashboardScreen(
                      eventId: token,
                      initialSchedule: TryoutSchedule.fromMap(token, pData),
                    ),
                  ),
                );
                return;
              }

              await _saveEntry(
                _HistoryItem(
                  title: title,
                  url: 'EXAMGO_TRYOUT://$token',
                  examId: token,
                ),
              );
              _confirmAndStart(
                'EXAMGO_TRYOUT://$token',
                title: title,
                examId: token,
              );
              return;
            }
          } catch (_) {}

          // 3. Fallback 2: Cek apakah token adalah tiket Lynk.id / Event (via LicenseService dengan fallback dual-layer)
          searchLoading.dismiss();

          final profile = await _promptUserProfileIfNeeded();
          if (profile == null || !mounted) return;

          final actLoading = ExamGoLoadingDialog.show(
            context,
            title: 'Mengaktifkan Tiket / Voucher...',
            message: 'Memverifikasi lisensi dengan server Lynk.id...',
          );

          final actResult = await LicenseService.instance.activateToken(
            rawToken: token,
            expectedType: 'STUDENT_LIFETIME',
            userName: profile['name'],
            userEmail: profile['email'],
            userWhatsapp: profile['whatsapp'],
          );

          actLoading.dismiss();

          if (actResult.isSuccess ||
              actResult.message.contains('aktif kembali')) {
            final targetExam = actResult.targetExamId;
            final isEvent =
                token.startsWith('EVENT') ||
                token.startsWith('EV') ||
                actResult.message.toLowerCase().contains('event') ||
                (targetExam != null &&
                    (targetExam.startsWith('EVENT') ||
                        targetExam.startsWith('EV')));

            final resolvedEventId =
                (targetExam != null &&
                    targetExam.isNotEmpty &&
                    targetExam != '-')
                ? targetExam
                : token;

            if (isEvent) {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDashboardScreen(
                      eventId: resolvedEventId,
                      eventToken: token,
                    ),
                  ),
                );
              }
            } else if (targetExam != null &&
                targetExam.isNotEmpty &&
                targetExam != '-') {
              _confirmAndStart(
                'EXAMGO_TRYOUT://$targetExam',
                title: 'Tryout Khusus',
                examId: targetExam,
              );
            } else {
              if (mounted) {
                setState(() {});
                _showError('Aktivasi Berhasil 🎉', actResult.message);
              }
            }
            return;
          }

          // Jika token tidak cocok di mana pun
          _showError(
            'Tidak Ditemukan',
            'Token ujian tidak valid atau sudah kadaluarsa.',
          );
        } catch (_) {
          searchLoading.dismiss();
          _showError(
            'Gagal Mencari',
            'Token ujian atau kode lisensi tidak valid. Pastikan perangkat terhubung ke internet dan periksa kembali kode Anda.',
          );
        }
      },
      child: Container(
        padding: EdgeInsets.all(context.rs(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
                Icons.keyboard_alt_rounded,
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
                    'Input Token Ujian',
                    style: GoogleFonts.poppins(
                      fontSize: context.rs(14),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Token ujian & tiket event Lynk.id',
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
                'Token',
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

  Widget _buildGeneratorCard() {
    return GestureDetector(
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final hasPin = prefs.getString('teacher_pin_hash') != null;
        if (!mounted) return;

        if (hasPin) {
          openTeacherMode(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Anda belum mengatur PIN. Silakan tap logo topi toga 7x untuk membuat PIN Mode Guru.',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: EdgeInsets.fromLTRB(
                context.rs(16),
                0,
                context.rs(16),
                context.rs(20),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      child: Container(
        padding: EdgeInsets.all(context.rs(16)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primaryGreen.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Riwayat ini hanya untuk dilihat. Silakan scan QR Code kembali jika ingin masuk ke ujian.',
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    backgroundColor: Colors.orange.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: EdgeInsets.fromLTRB(
                      context.rs(16),
                      0,
                      context.rs(16),
                      context.rs(20),
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.all(context.rs(14)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
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
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.orange,
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
            color: Colors.black.withValues(alpha: 0.04),
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
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
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
                        color: AppColors.primaryGreen.withValues(alpha: 0.12),
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

// ─── Clock Widget ─────────────────────────────────────────────────
/// FIX BUG-07+08: Clock widget terpisah agar hanya text jam yang rebuild
/// setiap detik, bukan seluruh HomeScreen widget tree.
/// Sekaligus fix timezone label: WIB (UTC+7) / WITA (UTC+8) / WIT (UTC+9).
class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  DateTime _time = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _time = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ags',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final d = dt.day.toString().padLeft(2, '0');
    final mo = months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    // FIX BUG-08: Deteksi timezone Indonesia berdasarkan UTC offset.
    // UTC+7 = WIB, UTC+8 = WITA, UTC+9 = WIT.
    final offset = dt.timeZoneOffset.inHours;
    final tz = offset >= 9
        ? 'WIT'
        : offset >= 8
        ? 'WITA'
        : 'WIB';
    return '$d $mo ${dt.year}  \u2022  $h:$m:$s $tz';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.access_time_rounded,
          color: Colors.white,
          size: context.rs(12),
        ),
        SizedBox(width: context.rs(6)),
        Text(
          _format(_time),
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: context.rs(10),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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

// ─────────────────────────────────────────────────────────────────
// ManualTokenInputDialog: Dialog modern serasi dengan _EventTokenDialog
// ─────────────────────────────────────────────────────────────────
class ManualTokenInputDialog extends StatefulWidget {
  const ManualTokenInputDialog({super.key});

  @override
  State<ManualTokenInputDialog> createState() => _ManualTokenInputDialogState();
}

class _ManualTokenInputDialogState extends State<ManualTokenInputDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _detectedType;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _ctrl.text.trim().toUpperCase();
    String? type;
    if (text.startsWith('EVENT') || text.startsWith('EV')) {
      type = 'Tiket Event Spesial';
    } else if (text.length == 6 && !text.contains('-')) {
      type = 'Token Ujian Guru (6 Digit)';
    } else if (text.contains('LYNK') || text.length > 8) {
      type = 'Voucher / Tiket Tryout';
    }
    if (type != _detectedType) {
      setState(() => _detectedType = type);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      final cleaned = data.text!.trim().toUpperCase().replaceAll(' ', '');
      setState(() {
        _ctrl.text = cleaned;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _ctrl.text.trim();
    final hasText = text.isNotEmpty;
    final isLong = text.length > 10;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 430),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 22,
                    horizontal: 20,
                  ),
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
                          Icons.vpn_key_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Input Token Ujian',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mendukung token 6-digit guru & tiket Event / Lynk.id',
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
                      // Token Type Chips
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.dialpad_rounded,
                                    size: 13,
                                    color: Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '6 Digit Guru',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFBBF7D0),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.confirmation_number_rounded,
                                    size: 13,
                                    color: AppColors.primaryGreen,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Tiket Event / Lynk',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryGreen,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'Kode Token / Tiket Ujian:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ctrl,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9\-_]'),
                          ),
                          TextInputFormatter.withFunction(
                            (old, val) => val.copyWith(
                              text: val.text.toUpperCase(),
                              selection: val.selection,
                            ),
                          ),
                        ],
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: isLong ? 14 : 16.5,
                          letterSpacing: isLong ? 0.8 : 1.5,
                          color: const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: '6 DIGIT / EVENT-XXXX',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12.5,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.normal,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.vpn_key_rounded,
                            size: 19,
                            color: AppColors.primaryGreen,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasText)
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  tooltip: 'Hapus',
                                  onPressed: () =>
                                      setState(() => _ctrl.clear()),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                tooltip: 'Tempel dari Clipboard',
                                onPressed: _pasteFromClipboard,
                              ),
                            ],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
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

                      if (_detectedType != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _detectedType!,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF166534),
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
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
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
                                  colors: [
                                    Color(0xFF1B5E20),
                                    AppColors.primaryGreen,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  final val = _ctrl.text.trim().toUpperCase();
                                  if (val.isNotEmpty) {
                                    Navigator.of(context).pop(val);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Cari Ujian',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
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

// ─────────────────────────────────────────────────────────────────
// StudentProfileDialog: Dialog biodata peserta tryout & event
// ─────────────────────────────────────────────────────────────────
class StudentProfileDialog extends StatefulWidget {
  final String initialName;
  final String initialEmail;
  final String initialWa;

  const StudentProfileDialog({
    super.key,
    required this.initialName,
    required this.initialEmail,
    required this.initialWa,
  });

  @override
  State<StudentProfileDialog> createState() => _StudentProfileDialogState();
}

class _StudentProfileDialogState extends State<StudentProfileDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _waCtrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _waCtrl = TextEditingController(text: widget.initialWa);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _waCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final wa = _waCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Silakan masukkan Nama Lengkap Anda');
      return;
    }
    if (wa.length < 8) {
      setState(() => _errorMessage = 'Nomor WhatsApp aktif minimal 8 digit');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_name', name);
    await prefs.setString('student_email', email.toLowerCase());
    await prefs.setString('student_whatsapp', wa);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 430),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 22,
                    horizontal: 20,
                  ),
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
                          Icons.person_pin_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Data Peserta Tryout',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lengkapi identitas untuk presensi ujian & sertifikat resmi',
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

                // Form Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nama Lengkap Siswa:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Misal: Ahmad Fauzan',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.person_outline_rounded,
                            size: 19,
                            color: AppColors.primaryGreen,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
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

                      const SizedBox(height: 12),

                      Text(
                        'No. WhatsApp Aktif:',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _waCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Misal: 081234567890',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.phone_android_rounded,
                            size: 19,
                            color: AppColors.primaryGreen,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
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

                      const SizedBox(height: 12),

                      Text(
                        'Email Siswa (Aktif):',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'nama@email.com',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 19,
                            color: AppColors.primaryGreen,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
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

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
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
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
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
                                  colors: [
                                    Color(0xFF1B5E20),
                                    AppColors.primaryGreen,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryGreen.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Simpan & Lanjut',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
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
