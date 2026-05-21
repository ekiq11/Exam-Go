import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:examgo/utils/webview_error_handler.dart';
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/constant/security_service.dart';
import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/services/exam_session_service.dart';
import 'package:examgo/services/monitoring_service.dart';
import 'package:examgo/services/qr_payload.dart';
import 'package:examgo/services/app_remote_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class ExamWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final String examId;
  final String studentName;
  final String studentNis;

  const ExamWebViewScreen({
    super.key,
    required this.url,
    this.title = '',
    this.examId = '',
    this.studentName = '',
    this.studentNis = '',
  });

  @override
  State<ExamWebViewScreen> createState() => _ExamWebViewScreenState();
}

class _ExamWebViewScreenState extends State<ExamWebViewScreen>
    with WidgetsBindingObserver {
  late final WebViewController _wvc;
  late final String _resolvedUrl;
  late String _examTitle;

  bool _loading = true;
  double _progress = 0;
  int _minimizeCount = 0;
  int _exitCount = 0;
  Timer? _exitTimer;
  bool _showExitBar = false;

  bool _isExiting = false;
  bool _kickedOut = false; // Flag khusus jika tertendang karena pelanggaran
  bool _securityEnabled = false;

  // Analytics
  DateTime? _examStartTime;

  // Exam Timer Overlay
  Timer? _examTimer;
  int _examElapsedSeconds = 0;

  // URL Whitelist — domain yang diizinkan selama ujian
  String _allowedHost = '';

  // Monitoring
  Timer? _pingTimer;
  StreamSubscription? _statusSub;
  bool _isFrozen = false;

  // Error handling & retry
  int _loadErrorCount = 0;
  Timer? _retryTimer;
  static const int _kMaxSilentRetry = 3;
  static const Duration _kRetryDelay = Duration(seconds: 5);

  // FIX BUG #2 helper: track apakah kita baru saja pause untuk
  // menghindari false-positive violation saat system UI muncul sebentar
  bool _wasActuallyPaused = false;
  Timer? _pauseDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final resolved = _resolveInput(widget.url);
    _resolvedUrl = resolved.url;
    _allowedHost = Uri.tryParse(resolved.url)?.host ?? '';
    _examTitle = widget.title.isNotEmpty
        ? widget.title
        : resolved.title.isNotEmpty
        ? resolved.title
        : Uri.tryParse(resolved.url)?.host ?? 'Ujian';
    _initWebView();
    _activateSecurity();
    AnalyticsService.instance.logScreenView(screenName: 'exam_webview');

    // FIX BUG-STREAM: Tambah guard studentNis.isNotEmpty.
    // studentNis kosong → path Firestore invalid (students/'') → "No active stream to cancel"
    // saat dispose() dipanggil sebelum stream fully connected.
    if (widget.examId.isNotEmpty && widget.studentNis.isNotEmpty) {
      _sendMonitoringStatus('ACTIVE');
      _pingTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        // FIX BUG-FREEZE: Jangan kirim 'ACTIVE' saat layar sedang dibekukan
        // oleh guru (BLOCKED). Ping ini akan menimpa status BLOCKED di Firestore
        // dan memicu stream listener untuk membuka freeze secara otomatis
        // tanpa persetujuan guru.
        if (!_isFrozen) _sendMonitoringStatus('ACTIVE');
      });
      _statusSub = MonitoringService.instance
          .streamStudentStatus(widget.examId, widget.studentNis)
          .listen(
            (doc) {
              if (!mounted) return;
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] as String?;
                if (status == 'ACTIVE' && _isFrozen) {
                  setState(() {
                    _minimizeCount = 0;
                    _isFrozen = false;
                    // FIX BUG-B: Reset _kickedOut agar dispose() bisa mengirim
                    // status FINISHED ke Firestore saat siswa keluar secara normal
                    // setelah guru membuka blokir. Tanpa ini, status siswa
                    // akan tetap BLOCKED meski ujian sudah selesai.
                    _kickedOut = false;
                  });
                  ExamSessionService.instance.updateViolations(0);
                  _sendMonitoringStatus('ACTIVE');
                } else if (status == 'BLOCKED' && !_isFrozen) {
                  setState(() {
                    _isFrozen = true;
                  });
                  // Catatan: _pingTimer dibiarkan berjalan agar bisa otomatis
                  // melanjutkan ping 'ACTIVE' saat guru membuka blokir (unfreeze).
                  // Logika di dalam _pingTimer sudah dilindungi oleh `if (!_isFrozen)`.
                }
              }
            },
            onError: (error) {
              // Abaikan error jaringan atau "No active stream to cancel"
            },
          );
    }
  }

  void _sendMonitoringStatus(String status) {
    if (widget.examId.isEmpty) return;
    MonitoringService.instance.updateStudentStatus(
      examId: widget.examId,
      nis: widget.studentNis,
      name: widget.studentName,
      status: status,
      violations: _minimizeCount,
    );
  }

  void _logActivity(String type, String description) {
    if (widget.examId.isEmpty || widget.studentNis.isEmpty) return;
    MonitoringService.instance.logActivity(
      examId: widget.examId,
      nis: widget.studentNis,
      activityType: type,
      description: description,
    );
  }

  /// Kirim notifikasi pelanggaran ke device guru via GAS.
  /// GAS membaca TEACHER_FCM_TOKEN dari Script Properties sendiri
  /// sehingga Flutter tidak perlu tahu/menyimpan token guru.
  /// Fire-and-forget — tidak ada await, tidak mengganggu UX siswa.
  void _notifyTeacherViaGas() {
    if (AppConfig.gasUrl.isEmpty || AppConfig.gasApiKey.isEmpty) return;
    http
        .post(
          Uri.parse(AppConfig.gasUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'apiKey': AppConfig.gasApiKey,
            'action': 'notify',
            'examId': widget.examId,
            'examTitle': _examTitle,
            'studentName': widget.studentName,
            'studentNis': widget.studentNis,
            'violations': _minimizeCount,
          }),
        )
        .timeout(const Duration(seconds: 15))
        .catchError((_) {
          // Abaikan semua error — notifikasi gagal tidak boleh mengganggu ujian
          return http.Response('', 500);
        });
  }

  // Simpan sesi ke disk agar bisa di-recover jika app crash
  Future<void> _saveSession() async {
    await ExamSessionService.instance.save(
      url: _resolvedUrl,
      title: _examTitle,
      examId: widget.examId,
      studentName: widget.studentName,
      studentNis: widget.studentNis,
      violations: _minimizeCount,
    );
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _examTimer?.cancel();
    _retryTimer?.cancel();
    _pauseDebounce?.cancel();
    _pingTimer?.cancel();
    // FIX BUG-STREAM: Gunakan catchError agar PlatformException "No active stream to cancel"
    // tidak propagasi ke Crashlytics jika dispose() dipanggil sebelum stream fully connected.
    _statusSub?.cancel().catchError((_) {});
    
    // Jangan timpa status BLOCKED dengan FINISHED jika siswa dikeluarkan paksa
    if (!_kickedOut) {
      _sendMonitoringStatus('FINISHED');
    }
    
    ExamSessionService.instance.clear(); // hapus sesi saat keluar normal
    WidgetsBinding.instance.removeObserver(this);
    if (_securityEnabled) {
      SecurityService.instance.disable(force: true).catchError((_) {
        SecurityService.instance.emergencyReset();
      });
    }
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    super.dispose();
  }

  Future<void> _activateSecurity() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await SecurityService.instance.enable();
    _securityEnabled = true;
    _examStartTime = DateTime.now();
    await _saveSession(); // simpan sesi ke disk
    // Mulai timer ujian
    _examTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _examElapsedSeconds++;
      // Update violations di storage setiap 30 detik
      if (_examElapsedSeconds % 30 == 0) {
        ExamSessionService.instance.updateViolations(_minimizeCount);
      }
    });
    await AnalyticsService.instance.logExamStarted(
      examTitle: _examTitle,
      examUrl: _resolvedUrl,
    );
    if (!mounted) return;
    setState(() {});

    _showSnack(
      '🔒 Ujian dimulai — mode kunci aktif',
      color: Colors.red.shade700,
      duration: 4,
    );
  }

  Timer? _inactiveTimer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isExiting || !_securityEnabled) return;

    switch (state) {
      case AppLifecycleState.paused:
        _inactiveTimer?.cancel();
        _pauseDebounce?.cancel();
        _pauseDebounce = Timer(const Duration(milliseconds: 300), () async {
          if (!mounted || _isExiting || !_securityEnabled) return;
          if (!_wasActuallyPaused) return;
          // FIX BUG-A: Jangan tambah violation saat layar sudah dibekukan guru.
          // Siswa menekan HOME saat melihat layar terkunci adalah wajar —
          // bukan pelanggaran baru.
          if (_isFrozen) return;

          final isScreenOn = await SecurityService.instance.isScreenOn();
          if (!isScreenOn && mounted) return;

          _minimizeCount++;
          _triggerVibrationAlarm();

          AnalyticsService.instance.logExamViolation(
            examTitle: _examTitle,
            violationCount: _minimizeCount,
          );

          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();

          // FIX AUDIT-3: Gunakan AppRemoteConfig.instance.maxViolations
          // sebagai threshold alih-alih hardcode 3.
          final maxViolations = AppRemoteConfig.instance.maxViolations > 0
              ? AppRemoteConfig.instance.maxViolations
              : 3;

          if (_minimizeCount >= maxViolations) {
            _kickedOut = true; // Tandai bahwa siswa ditendang paksa
            MonitoringService.instance.setLocalBlock(widget.examId, widget.studentNis); // Local fallback
            _logActivity(
              'EXIT_APP',
              'Keluar aplikasi (ke-$_minimizeCount×) — Diblokir karena membuka aplikasi lain (Browser/Chat/dll)',
            );
            _sendMonitoringStatus('BLOCKED');
            // Kirim FCM ke guru — siswa mencapai batas maksimal pelanggaran
            _notifyTeacherViaGas();
            _showSnack(
              '⚠️ Peringatan ke-$_minimizeCount: Pelanggaran telah dicatat dan dilaporkan ke pengawas ujian.',
              color: Colors.red.shade800,
              duration: 5,
            );
            _performExit(null, 'blocked_violation');
          } else {
            _logActivity(
              'EXIT_APP',
              'Keluar aplikasi (ke-$_minimizeCount×) — Peringatan membuka aplikasi lain',
            );
            _sendMonitoringStatus('PAUSED');
            // Kirim FCM ke guru di setiap pelanggaran agar guru bisa memantau
            // secara real-time, tidak hanya saat siswa diblokir.
            _notifyTeacherViaGas();
            _showMinimizeWarning();
            _showViolationDialog();
          }
        });
        _wasActuallyPaused = true;
        break;

      case AppLifecycleState.inactive:
        // Pada iOS, notification center membuat app masuk ke inactive.
        // Beri waktu 1.5 detik. Jika masih inactive, anggap pelanggaran.
        _inactiveTimer?.cancel();
        _inactiveTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted || _isExiting || !_securityEnabled) return;
          // FIX BUG-09: Cegah double-trigger violation.
          // Jika paused debounce sudah aktif (dari transition inactive→paused),
          // atau jika wasActuallyPaused sudah di-set true oleh paused handler,
          // jangan mulai violation baru dari inactive timer.
          if (_pauseDebounce?.isActive == true) return;
          if (_wasActuallyPaused) return;
          _wasActuallyPaused = true;
          didChangeAppLifecycleState(AppLifecycleState.paused);
        });
        break;

      case AppLifecycleState.resumed:
        _inactiveTimer?.cancel();
        if (!_wasActuallyPaused) return;
        _wasActuallyPaused = false;

        SecurityService.instance.isScreenOn().then((isScreenOn) {
          if (!isScreenOn && mounted) return;
          _sendMonitoringStatus('ACTIVE');
          if (mounted && _securityEnabled) {
            SecurityService.instance.reapply();
          }
        });
        break;

      default:
        break;
    }
  }

  void _triggerVibrationAlarm() async {
    // Memberikan feedback getar bertubi-tubi seperti alarm
    for (int i = 0; i < 6; i++) {
      if (!mounted) break;
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  void _showMinimizeWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: context.rs(4)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.gpp_maybe_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Peringatan Pelanggaran!', style: GoogleFonts.poppins(fontSize: context.rs(13), fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('Dilarang keluar aplikasi ($_minimizeCount× terdeteksi)', style: GoogleFonts.poppins(fontSize: context.rs(11), color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.red.shade800.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        margin: EdgeInsets.fromLTRB(context.rs(20), 0, context.rs(20), context.rs(80)),
      ),
    );
  }

  void _showViolationDialog() {
    if (!mounted) return;
    final maxViolations = AppRemoteConfig.instance.maxViolations > 0
        ? AppRemoteConfig.instance.maxViolations
        : 3;
        
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Circle
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.gpp_maybe_rounded, color: Colors.red.shade600, size: 48),
              ),
              const SizedBox(height: 24),
              
              // Title
              Text(
                'Peringatan Sistem!',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              
              // Description
              Text(
                'Anda terdeteksi meninggalkan layar ujian. Aktivitas ini telah dicatat dan dilaporkan secara Live ke pengawas ujian.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // Status Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_rounded, size: 18, color: Colors.red.shade400),
                        const SizedBox(width: 8),
                        Text('Sisa Toleransi:', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade900)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${maxViolations - _minimizeCount}x Lagi',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Saya Mengerti',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
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

  Future<void> _initWebView() async {
    late final PlatformWebViewControllerCreationParams params;
    if (!kIsWeb && Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = AndroidWebViewControllerCreationParams();
    }

    _wvc = WebViewController.fromPlatformCreationParams(params)
      ..setUserAgent('ExamGo-Secure-Browser/2.1.0')
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
              });
            }
            _loadErrorCount = 0;
            _retryTimer?.cancel();
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _loadErrorCount = 0;
            _injectSecurityJS();
          },
          onNavigationRequest: (req) {
            if (!_securityEnabled) return NavigationDecision.navigate;
            if (_allowedHost.isEmpty) return NavigationDecision.navigate;
            final uri = Uri.tryParse(req.url);
            final scheme = uri?.scheme ?? '';
            if (scheme != 'http' && scheme != 'https') {
              return NavigationDecision.navigate;
            }
            final reqHost = uri?.host ?? '';
            if (reqHost.isEmpty) return NavigationDecision.navigate;
            if (reqHost == _allowedHost || reqHost.endsWith('.$_allowedHost')) {
              return NavigationDecision.navigate;
            }
            _showSnack(
              '🚫 Navigasi ke domain lain diblokir selama ujian',
              color: Colors.red.shade700,
              duration: 3,
            );
            return NavigationDecision.prevent;
          },
          onWebResourceError: (e) {
            if (!mounted) return;
            final isMainFrame = e.isForMainFrame ?? true;
            if (!isMainFrame) return;
            if (e.errorCode == -6) return;
            if (e.errorCode == -3) return;

            final msg = e.description;
            _loadErrorCount++;
            
            final isSilentRetry = WebViewErrorHandler.shouldRetrySilently(e.errorCode);
            final userMessage = WebViewErrorHandler.getErrorMessage(e.errorCode, msg);

            if (isSilentRetry && _loadErrorCount <= _kMaxSilentRetry) {
              _retryTimer?.cancel();
              _retryTimer = Timer(_kRetryDelay, () {
                if (mounted && !_isExiting) _wvc.reload();
              });
              _showSnack(
                '🔄 Mencoba ulang... ($_loadErrorCount/$_kMaxSilentRetry)',
                color: Colors.orange.shade700,
                duration: 3,
              );
            } else {
              _showSnack(
                '⚠️ $userMessage',
                color: Colors.red.shade800,
                duration: 5,
              );
              AnalyticsService.instance.logExamLoadError(
                examHost: Uri.tryParse(_resolvedUrl)?.host ?? 'unknown',
                errorMessage: msg,
                errorCode: e.errorCode,
                retryCount: _loadErrorCount - 1,
              );
              _showLoadError(msg);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'ExamGoChannel',
        onMessageReceived: (msg) {
          if (msg.message == 'SCREENSHOT_ATTEMPT') {
            _logActivity(
              'SCREENSHOT',
              'Percobaan screenshot / cetak layar terdeteksi',
            );
            _showSnack(
              '📵 Screenshot diblokir!',
              color: Colors.red.shade700,
              duration: 2,
            );
          } else if (msg.message == 'VISIBILITY_HIDDEN') {
            // Dicatat tapi tidak trigger pelanggaran — bisa jadi notifikasi
            _logActivity(
              'SCREEN_HIDDEN',
              'Layar disembunyikan (Siswa terdeteksi berpindah ke aplikasi lain / Home Screen)',
            );
          }
        },
      )
      ..loadRequest(
        Uri.parse(_resolvedUrl),
        headers: {'Accept-Language': 'id-ID,id;q=0.9,*;q=0.5'},
      );

    // ── Android: konfigurasi tambahan ─────────────────────────
    if (!kIsWeb && Platform.isAndroid) {
      AndroidWebViewController.enableDebugging(false);

      final androidController = _wvc.platform as AndroidWebViewController;
      await androidController.setOnPlatformPermissionRequest(
        (request) => request.grant(),
      );
      // Nonaktifkan tawaran translate dari Android WebView dengan mengirimkan
      // header Accept-Language yang menyamakan bahasa konten dengan locale device.
      // (Header diset via loadRequest di atas).
    }

    // ── iOS: konfigurasi tambahan WKWebView ─────────────────
    if (!kIsWeb && Platform.isIOS) {
      final wk = _wvc.platform as WebKitWebViewController;
      wk.setAllowsBackForwardNavigationGestures(false);
      wk.setInspectable(false);
    }
  }

  Widget _buildWebViewWidget() {
    if (!kIsWeb && Platform.isAndroid) {
      // FIX BUG-03: AndroidWebViewWidget tidak bisa langsung direturn sebagai Widget
      // karena tipe-nya adalah PlatformWebViewWidget, bukan Widget.
      // Bungkus dengan Builder agar widget tree tetap benar tanpa panggil .build() manual.
      return Builder(
        builder: (ctx) => AndroidWebViewWidget(
          AndroidWebViewWidgetCreationParams(
            controller: _wvc.platform as AndroidWebViewController,
            displayWithHybridComposition: false,
          ),
        ).build(ctx),
      );
    }
    return WebViewWidget(
      controller: _wvc,
      layoutDirection: TextDirection.ltr,
      gestureRecognizers: const {},
    );
  }

  void _injectSecurityJS() {
    _wvc
        .runJavaScript('''
      (function(){
        // --- Blokir copy-paste & klik kanan ---
        document.addEventListener('contextmenu', e => e.preventDefault());
        document.addEventListener('copy',        e => e.preventDefault());
        document.addEventListener('cut',         e => e.preventDefault());
        document.addEventListener('paste',       e => e.preventDefault());
        document.addEventListener('selectstart', e => e.preventDefault());
        try { document.body.style.webkitUserSelect = 'none'; } catch(_){}
        try { document.body.style.userSelect = 'none'; } catch(_){}
        // Blokir Print Screen / PrintDialog — notifikasi ke Flutter
        document.addEventListener('keydown', function(e) {
          if (e.key === 'PrintScreen' || (e.ctrlKey && (e.key==='p'||e.key==='s'||e.key==='a'))) {
            e.preventDefault();
            try { ExamGoChannel.postMessage('SCREENSHOT_ATTEMPT'); } catch(_){}
          }
        });
        // Deteksi screenshot Android (visibilitychange ke hidden)
        document.addEventListener('visibilitychange', function() {
          if (document.visibilityState === 'hidden') {
            try { ExamGoChannel.postMessage('VISIBILITY_HIDDEN'); } catch(_){}
          }
        });
        // Blokir window.open agar tidak bisa membuka tab baru
        window.open = function(){ return null; };
        window.addEventListener('beforeunload', function(e) {
          e.stopImmediatePropagation();
        }, true);
        // --- Nonaktifkan fitur Translate browser ---
        // Mencegah siswa menerjemahkan soal berbahasa Inggris via
        // Google Translate bar (Android WebView/Chrome) atau popup translate.
        // Cara 1: set meta tag "google" notranslate
        (function() {
          var meta = document.querySelector('meta[name="google"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'google';
            document.head.appendChild(meta);
          }
          meta.content = 'notranslate';
        })();
        // Cara 2: tambahkan class "notranslate" ke <html> — dikenali WebView & Chrome
        try { document.documentElement.classList.add('notranslate'); } catch(_){}
        // Cara 3: set lang ke bahasa halaman agar WebView tidak menawarkan translate
        // (WebView hanya menawarkan translate jika lang berbeda dari locale device)
        try {
          if (!document.documentElement.getAttribute('translate')) {
            document.documentElement.setAttribute('translate', 'no');
          }
        } catch(_){}
        // Keep-alive ping ke server ujian
        if (!window.__examgoKA) {
          window.__examgoKA = setInterval(function() {
            try { fetch(window.location.href, { method: 'HEAD', cache: 'no-store', credentials: 'include' }).catch(function(){}); } catch(_){}
          }, 60000);
        }
      })();
    ''')
        .catchError((_) {});
  }

  void _showLoadError(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: EdgeInsets.all(context.rs(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(14)),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.red,
                  size: context.rs(36),
                ),
              ),
              SizedBox(height: context.rs(14)),
              Text(
                'Gagal Memuat',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(16),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: context.rs(8)),
              Text(
                'Koneksi gagal setelah $_loadErrorCount× percobaan.\n$msg',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(12),
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.rs(22)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Tutup',
                        style: GoogleFonts.poppins(fontSize: context.rs(13)),
                      ),
                    ),
                  ),
                  SizedBox(width: context.rs(10)),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _loadErrorCount = 0;
                        _wvc.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        'Muat Ulang',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(13),
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onExitPress() {
    if (_isExiting) return;
    _exitCount++;
    HapticFeedback.mediumImpact();
    _exitTimer?.cancel();
    if (mounted) setState(() => _showExitBar = true);

    if (_exitCount == 1) {
      _logActivity(
        'EXIT_ATTEMPT',
        'Menekan tombol Keluar Ujian (ke-$_exitCount×)',
      );
      AnalyticsService.instance.logExitAttempt(
        attemptNumber: _minimizeCount,
        minimizeCount: _minimizeCount,
      );
    }

    if (_exitCount >= AppConfig.exitPressRequired) {
      _showExitDialog();
    } else {
      _exitTimer = Timer(
        Duration(seconds: AppConfig.exitPressWindowSeconds),
        () {
          if (mounted) {
            setState(() {
              _exitCount = 0;
              _showExitBar = false;
            });
          }
        },
      );
    }
  }

  void _showExitDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: EdgeInsets.all(context.rs(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(16)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade600, Colors.red.shade400],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: context.rs(30),
                ),
              ),
              SizedBox(height: context.rs(16)),
              Text(
                'Keluar dari Ujian?',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: context.rs(10)),
              if (_examTitle.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rs(14),
                    vertical: context.rs(10),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paleGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.school,
                        color: AppColors.primaryGreen,
                        size: 15,
                      ),
                      SizedBox(width: context.rs(7)),
                      Flexible(
                        child: Text(
                          _examTitle,
                          style: GoogleFonts.poppins(
                            fontSize: context.rs(13),
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: context.rs(12)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(context.rs(12)),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'Anda yakin ingin keluar?\nProgress yang belum tersimpan akan hilang.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(12),
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_minimizeCount > 0) ...[
                      SizedBox(height: context.rs(10)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(12),
                          vertical: context.rs(7),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$_minimizeCount× percobaan keluar terdeteksi',
                              style: GoogleFonts.poppins(
                                fontSize: context.rs(11),
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: context.rs(20)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        if (mounted) {
                          setState(() {
                            _exitCount = 0;
                            _showExitBar = false;
                          });
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Lanjutkan',
                        style: GoogleFonts.poppins(fontSize: context.rs(14)),
                      ),
                    ),
                  ),
                  SizedBox(width: context.rs(12)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _performExit(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: context.rs(13)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Ya, Keluar',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(14),
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _performExit([BuildContext? dialogCtx, String? exitReason]) async {
    if (_isExiting) return;
    _isExiting = true;
    _securityEnabled = false;
    if (dialogCtx != null && dialogCtx.mounted) Navigator.of(dialogCtx).pop();
    _exitTimer?.cancel();
    final duration = _examStartTime != null
        ? DateTime.now().difference(_examStartTime!).inSeconds
        : 0;
    await AnalyticsService.instance.logExamEnded(
      examTitle: _examTitle,
      durationSeconds: duration,
      minimizeCount: _minimizeCount,
    );
    try {
      await SecurityService.instance.disable(force: true);
    } catch (_) {
      await SecurityService.instance.emergencyReset();
    }

    // Auto-Clear Cache & Cookies untuk keamanan perangkat bersama
    try {
      await _wvc.clearCache();
      await _wvc.clearLocalStorage();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) Navigator.of(context).pop(exitReason);
  }

  void _onRefresh() {
    HapticFeedback.lightImpact();
    _wvc.reload();
    _showSnack('Memuat ulang…', color: AppColors.primaryGreen, duration: 2);
  }

  void _showSnack(String msg, {required Color color, int duration = 3}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: context.rs(13)),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: duration),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.fromLTRB(
          context.rs(16),
          0,
          context.rs(16),
          context.rs(80),
        ),
      ),
    );
  }

  ({String url, String title}) _resolveInput(String raw) {
    // [FIX R-5] Tambahkan curly braces pada if statement
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return (url: raw, title: '');
    }
    try {
      final p = QRPayloadService.validate(raw);
      if (p != null) return (url: p.url, title: p.title);
    } catch (_) {}
    try {
      final w = 'https://$raw';
      if (Uri.parse(w).host.isNotEmpty) return (url: w, title: '');
    } catch (_) {}
    return (url: raw, title: '');
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _isExiting || !_securityEnabled;

    // FIX BUG #7: PopScope.onPopInvoked deprecated di Flutter 3.22+.
    // Diganti dengan onPopInvokedWithResult yang menerima generic result.
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _securityEnabled && !_isExiting) _showMinimizeWarning();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildHeader(),
            if (_loading)
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey.shade100,
                valueColor: const AlwaysStoppedAnimation(
                  AppColors.primaryGreen,
                ),
                minHeight: 3,
              ),
            Expanded(
              child: Stack(
                children: [
                  _buildWebViewWidget(),
                  if (_showExitBar)
                    Positioned(
                      top: context.rs(12),
                      left: context.rs(12),
                      right: context.rs(12),
                      child: _buildExitBar(),
                    ),
                  if (_securityEnabled)
                    Positioned(
                      bottom: context.rs(12),
                      left: context.rs(12),
                      child: _buildLockBadge(),
                    ),
                  if (_minimizeCount > 0)
                    Positioned(
                      top: _showExitBar ? null : context.rs(12),
                      bottom: _showExitBar ? context.rs(12) : null,
                      right: context.rs(12),
                      child: _buildMinimizeBadge(),
                    ),
                  if (_isFrozen)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.9),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_rounded,
                                size: 64,
                                color: Colors.redAccent,
                              ),
                              SizedBox(height: context.rs(16)),
                              Text(
                                'Layar Dibekukan!',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: context.rs(24),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: context.rs(8)),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: context.rs(32),
                                ),
                                child: Text(
                                  'Anda telah melakukan pelanggaran batas maksimal. Silakan lapor ke pengawas untuk membuka kunci agar dapat melanjutkan ujian.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: context.rs(14),
                                  ),
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
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), AppColors.primaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + context.rs(10),
          bottom: context.rs(13),
          left: context.rs(16),
          right: context.rs(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            SizedBox(width: context.rs(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _examTitle,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: context.rs(14),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Exam Timer & Real-time Clock
                  _LiveTimerWidget(startTime: _examStartTime),
                ],
              ),
            ),
            if (_minimizeCount > 0) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(8),
                  vertical: context.rs(4),
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 11,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$_minimizeCount×',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: context.rs(10),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: context.rs(6)),
            ],
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(9),
                vertical: context.rs(4),
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFA5D6A7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Live',
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
      ),
    );
  }

  Widget _buildExitBar() {
    return Container(
      padding: EdgeInsets.all(context.rs(14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade700, Colors.red.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERINGATAN KELUAR',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: context.rs(12),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tekan ${AppConfig.exitPressRequired - _exitCount}× lagi dalam ${AppConfig.exitPressWindowSeconds} detik',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: context.rs(11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.rs(8)),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _exitCount / AppConfig.exitPressRequired,
              backgroundColor: Colors.white30,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockBadge() =>
      _badge('TERKUNCI', Icons.lock_rounded, const Color(0xFF1B5E20));
  Widget _buildMinimizeBadge() => _badge(
    '$_minimizeCount×',
    Icons.warning_amber_rounded,
    Colors.orange.shade600,
  );

  Widget _badge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.rs(20),
            vertical: context.rs(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _BottomBtn(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                  color: AppColors.primaryGreen,
                  onTap: _onRefresh,
                ),
              ),
              SizedBox(width: context.rs(12)),
              Expanded(
                child: _BottomBtn(
                  icon: Icons.logout_rounded,
                  label: 'Keluar',
                  color: Colors.red,
                  onTap: _onExitPress,
                  trailingIcon: Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? trailingIcon;
  const _BottomBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: context.rs(13)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.82)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: context.rs(20)),
            SizedBox(width: context.rs(7)),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: context.rs(14),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trailingIcon != null) ...[
              SizedBox(width: context.rs(4)),
              Icon(trailingIcon!, color: Colors.white, size: context.rs(13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Live Timer Widget ──────────────────────────────────────────────────
// Memisahkan clock & durasi agar tidak memicu rebuild WebView setiap detik
class _LiveTimerWidget extends StatefulWidget {
  final DateTime? startTime;
  const _LiveTimerWidget({required this.startTime});

  @override
  State<_LiveTimerWidget> createState() => _LiveTimerWidgetState();
}

class _LiveTimerWidgetState extends State<_LiveTimerWidget> {
  late DateTime _currentTime;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
          if (widget.startTime != null) {
            _elapsedSeconds = _currentTime
                .difference(widget.startTime!)
                .inSeconds;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final offset = _currentTime.timeZoneOffset.inHours;
    final tz = offset >= 9
        ? 'WIT'
        : offset >= 8
        ? 'WITA'
        : 'WIB';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 10,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 3),
        Text(
          _formatDuration(_elapsedSeconds),
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: context.rs(10),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.access_time_rounded,
          size: 10,
          color: Colors.white.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 3),
        Text(
          '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')} $tz',
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: context.rs(10),
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
