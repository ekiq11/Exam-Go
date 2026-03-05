// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io' show Platform;
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/constant/security_service.dart';
import 'package:examgo/firebas_analytics/analytic_service.dart';
import 'package:examgo/services/qr_payload.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class ExamWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  const ExamWebViewScreen({super.key, required this.url, this.title = ''});

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
  Timer? _uiTimer;
  bool _isExiting = false;
  bool _securityEnabled = false;

  // Analytics
  DateTime? _examStartTime;

  // Error handling & retry
  int _loadErrorCount = 0;
  Timer? _retryTimer;
  static const int _kMaxSilentRetry = 2;
  static const Duration _kRetryDelay = Duration(seconds: 3);

  // Render process crash recovery — ditangani di MainActivity.kt (native)
  // Variable ini dipakai agar onWebResourceError tidak double-handle
  bool _renderCrashed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final resolved = _resolveInput(widget.url);
    _resolvedUrl = resolved.url;
    _examTitle = widget.title.isNotEmpty
        ? widget.title
        : resolved.title.isNotEmpty
        ? resolved.title
        : Uri.tryParse(resolved.url)?.host ?? 'Ujian';
    _initWebView();
    _activateSecurity();
    AnalyticsService.instance.logScreenView(screenName: 'exam_webview');
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    _uiTimer?.cancel();
    _retryTimer?.cancel();
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
    await AnalyticsService.instance.logExamStarted(
      examTitle: _examTitle,
      examUrl: _resolvedUrl,
    );
    if (!mounted) return;
    setState(() {});
    _uiTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _securityEnabled && !_isExiting) {
        SecurityService.instance.reapply();
      }
    });
    _showSnack(
      '🔒 Ujian dimulai — mode kunci aktif',
      color: Colors.red.shade700,
      duration: 4,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isExiting || !_securityEnabled) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _minimizeCount++;
        HapticFeedback.heavyImpact();
        _showMinimizeWarning();
        AnalyticsService.instance.logExamViolation(
          examTitle: _examTitle,
          violationCount: _minimizeCount,
        );
        break;
      case AppLifecycleState.resumed:
        SecurityService.instance.reapply();
        break;
      default:
        break;
    }
  }

  void _showMinimizeWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '⚠️ Dilarang keluar saat ujian! ($_minimizeCount× terdeteksi)',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(13),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
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

  void _initWebView() {
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
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (_) {
            if (mounted)
              setState(() {
                _loading = true;
                _renderCrashed = false;
              });
            _loadErrorCount = 0;
            _retryTimer?.cancel();
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _loadErrorCount = 0;
            _injectSecurityJS();
          },
          onWebResourceError: (e) {
            if (!mounted) return;
            final isMainFrame = e.isForMainFrame ?? true;
            if (!isMainFrame) return;
            if (e.errorCode == -6) return;
            // Render process crash sudah di-handle di MainActivity.kt
            // Saat crash terjadi, native mengembalikan true sehingga
            // onWebResourceError tetap terpanggil — kita retry di sini
            final msg = e.description ?? 'Koneksi bermasalah';
            _loadErrorCount++;
            AnalyticsService.instance.logExamLoadError(
              examHost: Uri.tryParse(_resolvedUrl)?.host ?? 'unknown',
              errorMessage: msg,
            );
            if (_loadErrorCount <= _kMaxSilentRetry) {
              _retryTimer?.cancel();
              _retryTimer = Timer(_kRetryDelay, () {
                if (mounted && !_isExiting) _wvc.reload();
              });
              _showSnack(
                '🔄 Koneksi terputus, mencoba ulang... ($_loadErrorCount/$_kMaxSilentRetry)',
                color: Colors.orange.shade700,
                duration: 3,
              );
            } else {
              _showLoadError(msg);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_resolvedUrl));

    // Matikan remote debug inspector di production
    if (!kIsWeb && Platform.isAndroid) {
      AndroidWebViewController.enableDebugging(false);
    }

    // iOS: konfigurasi tambahan WKWebView
    if (!kIsWeb && Platform.isIOS) {
      final wk = _wvc.platform as WebKitWebViewController;
      wk.setAllowsBackForwardNavigationGestures(false);
      wk.setInspectable(false);
    }
  }

  void _injectSecurityJS() {
    _wvc
        .runJavaScript('''
      (function(){
        document.addEventListener('contextmenu', e => e.preventDefault());
        document.addEventListener('selectstart', e => e.preventDefault());
        try { document.body.style.webkitUserSelect = 'none'; } catch(_){}
        try { document.body.style.userSelect = 'none'; } catch(_){}
        window.open = function(){ return null; };
        window.addEventListener('beforeunload', function(e) {
          e.stopImmediatePropagation();
        }, true);
        if (!window.__examgoKA) {
          window.__examgoKA = setInterval(function() {
            try { fetch(window.location.href, { method: 'HEAD', cache: 'no-store', credentials: 'include' }).catch(function(){}); } catch(_){}
          }, 25000);
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
    AnalyticsService.instance.logExitAttempt(
      attemptNumber: _exitCount,
      minimizeCount: _minimizeCount,
    );
    if (_exitCount >= AppConfig.exitPressRequired) {
      _showExitDialog();
    } else {
      _exitTimer = Timer(
        Duration(seconds: AppConfig.exitPressWindowSeconds),
        () {
          if (mounted)
            setState(() {
              _exitCount = 0;
              _showExitBar = false;
            });
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
                      color: Colors.red.withOpacity(0.3),
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
                        if (mounted)
                          setState(() {
                            _exitCount = 0;
                            _showExitBar = false;
                          });
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

  Future<void> _performExit(BuildContext dialogCtx) async {
    if (_isExiting) return;
    _isExiting = true;
    _securityEnabled = false;
    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
    _uiTimer?.cancel();
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
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) Navigator.of(context).pop();
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
    if (raw.startsWith('http://') || raw.startsWith('https://'))
      return (url: raw, title: '');
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
    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
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
                  WebViewWidget(controller: _wvc),
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
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.22),
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
                  Text(
                    'Ujian sedang berlangsung',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: context.rs(10),
                    ),
                  ),
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
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
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
                  color: Colors.white.withOpacity(0.2),
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
                        color: Colors.white.withOpacity(0.9),
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
        color: color.withOpacity(0.9),
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
            color: Colors.black.withOpacity(0.07),
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
            colors: [color, color.withOpacity(0.82)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
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
