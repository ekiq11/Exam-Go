// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:examgo/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

double _responsiveFontSize(double baseSize, BuildContext context) {
  final shortestSide = MediaQuery.of(context).size.shortestSide;
  final scale = (shortestSide / 360.0).clamp(0.85, 1.25);
  return baseSize * scale;
}

double _responsivePadding(double baseValue, BuildContext context) {
  return _responsiveFontSize(baseValue, context);
}

double _responsiveIconSize(double baseSize, BuildContext context) {
  return _responsiveFontSize(baseSize, context);
}

class QRWebViewScreen extends StatefulWidget {
  final String url;

  const QRWebViewScreen({super.key, required this.url});

  @override
  State<QRWebViewScreen> createState() => _QRWebViewScreenState();
}

class _QRWebViewScreenState extends State<QRWebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  String _currentUrl = '';
  double _loadingProgress = 0.0;
  bool _isLockTaskModeActive = false;
  Timer? _uiMonitoringTimer;
  Timer? _lifecycleMonitoringTimer;
  int _minimizeAttempts = 0;
  
  // Method Channel untuk Native Lock Task
  static const platform = MethodChannel('com.examgo/locktask');
  
  // Exit security variables
  int _exitPressCount = 0;
  Timer? _exitTimer;
  bool _showExitWarning = false;
  static const int REQUIRED_PRESS_COUNT = 5;
  static const int PRESS_DURATION_SECONDS = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _initializeWebView();
    _enableLockTaskMode();
  }

  /// ==================== LOCK TASK MODE ====================
  
  Future<void> _enableLockTaskMode() async {
    try {
      // STEP 1: Enable Immersive Mode
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      
      // STEP 2: Lock Orientation
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      
      // STEP 3: Hide System UI
       SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );
      
      // STEP 4: Start Native Lock Task (akan mencoba, jika gagal tetap lanjut)
      try {
        final result = await platform.invokeMethod('startLockTask');
        print('🔒 Native Lock Task: $result');
      } catch (e) {
        print('⚠️ Native Lock Task not available (normal tanpa Device Admin): $e');
      }
      
      setState(() => _isLockTaskModeActive = true);
      
      // STEP 5: Start aggressive monitoring
      _startUIMonitoring();
      _startLifecycleMonitoring();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.lock, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '🔒 Mode Kunci Aktif - Aplikasi terkunci!',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
      
      print('✅ Lock Task Mode Enabled (Multi-layer protection)');
    } catch (e) {
      print('❌ Error enabling lock task mode: $e');
    }
  }

  Future<void> _disableLockTaskMode() async {
    try {
      // Stop monitoring first
      _stopUIMonitoring();
      _stopLifecycleMonitoring();
      
      // Try to stop native lock task
      try {
        await platform.invokeMethod('stopLockTask');
      } catch (e) {
        print('Native lock task stop: $e');
      }
      
      // Restore system UI
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
      
      // Unlock orientation
      await SystemChrome.setPreferredOrientations([]);
      
      setState(() => _isLockTaskModeActive = false);
      
      print('✅ Lock Task Mode Disabled');
    } catch (e) {
      print('❌ Error disabling lock task mode: $e');
    }
  }

  /// ==================== AGGRESSIVE MONITORING ====================
  
  /// Monitor UI visibility every 200ms (FAST)
  void _startUIMonitoring() {
    _uiMonitoringTimer = Timer.periodic(Duration(milliseconds: 200), (_) {
      if (_isLockTaskModeActive) {
        // Aggressively re-apply immersive mode
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: [],
        );
      }
    });
  }

  void _stopUIMonitoring() {
    _uiMonitoringTimer?.cancel();
    _uiMonitoringTimer = null;
  }

  /// Monitor app lifecycle every 300ms (DETECT minimize attempts)
  void _startLifecycleMonitoring() {
    _lifecycleMonitoringTimer = Timer.periodic(Duration(milliseconds: 300), (_) {
      // This will be caught by didChangeAppLifecycleState
      // Just keep monitoring to ensure app stays in foreground
    });
  }

  void _stopLifecycleMonitoring() {
    _lifecycleMonitoringTimer?.cancel();
    _lifecycleMonitoringTimer = null;
  }

  /// ==================== APP LIFECYCLE DETECTION ====================
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    print('📱 App Lifecycle: $state');
    
    if (state == AppLifecycleState.paused) {
      // APP IS BEING MINIMIZED OR SWITCHED!
      if (_isLockTaskModeActive) {
        _minimizeAttempts++;
        print('🚨 MINIMIZE ATTEMPT DETECTED! Count: $_minimizeAttempts');
        
        HapticFeedback.heavyImpact();
        
        // Show strong warning
        _showMinimizeWarning();
        
        // Force app back to foreground (try)
        _bringAppToForeground();
      }
    } else if (state == AppLifecycleState.inactive) {
      // Transitioning state - also block
      if (_isLockTaskModeActive) {
        print('⚠️ App going inactive - attempting to restore');
        _bringAppToForeground();
      }
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground
      print('✅ App resumed');
      if (_isLockTaskModeActive) {
        // Re-apply all protections
        _enableLockTaskMode();
      }
    }
  }

  /// Force bring app to foreground
  Future<void> _bringAppToForeground() async {
    try {
      // Re-apply immersive mode
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      
      // Try native method to bring to front
      try {
        await platform.invokeMethod('bringToForeground');
      } catch (e) {
        print('Native bring to foreground not available: $e');
      }
    } catch (e) {
      print('Error bringing app to foreground: $e');
    }
  }

  void _showMinimizeWarning() {
    if (!mounted) return;
    
    // Cancel previous warnings
    ScaffoldMessenger.of(context).clearSnackBars();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🚨 PERINGATAN!',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Tidak boleh keluar dari aplikasi saat ujian!',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Percobaan minimize: $_minimizeAttempts kali',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  /// ==================== WEBVIEW SETUP ====================
  
  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() => _loadingProgress = progress / 100);
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
            // Inject JavaScript to disable right-click & text selection
            _webViewController.runJavaScript('''
              document.addEventListener('contextmenu', event => event.preventDefault());
              document.addEventListener('selectstart', event => event.preventDefault());
              document.body.style.webkitUserSelect = 'none';
              document.body.style.userSelect = 'none';
              
              // Prevent opening links in new window/tab
              window.open = function() { return null; };
            ''');
          },
          onWebResourceError: (error) {
            _showErrorDialog(error.description ?? 'Terjadi kesalahan jaringan.');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: _responsiveIconSize(20, context)),
            SizedBox(width: _responsivePadding(8, context)),
            Expanded(
              child: Text(
                'Error Memuat Halaman',
                style: GoogleFonts.poppins(
                  fontSize: _responsiveFontSize(16, context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(message, style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text('Tutup', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _webViewController.reload();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            child: Text('Muat Ulang', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
          ),
        ],
      ),
    );
  }

  /// ==================== EXIT HANDLING ====================
  
  void _handleExitPress() {
    _exitPressCount++;
    _exitTimer?.cancel();
    HapticFeedback.mediumImpact();
    
    setState(() => _showExitWarning = true);
    
    if (_exitPressCount >= REQUIRED_PRESS_COUNT) {
      HapticFeedback.heavyImpact();
      _showExitConfirmationDialog();
    } else {
      _exitTimer = Timer(Duration(seconds: PRESS_DURATION_SECONDS), () {
        setState(() {
          _exitPressCount = 0;
          _showExitWarning = false;
        });
      });
    }
  }

  void _showExitConfirmationDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(_responsivePadding(24, context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(_responsivePadding(16, context)),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.exit_to_app, 
                  size: _responsiveIconSize(48, context), 
                  color: Colors.red
                ),
              ),
              SizedBox(height: _responsivePadding(20, context)),
              Text(
                'Keluar dari Ujian?',
                style: GoogleFonts.poppins(
                  fontSize: _responsiveFontSize(18, context),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: _responsivePadding(12, context)),
              Text(
                'Anda yakin ingin keluar dari ujian?\n\nData yang belum disimpan akan hilang.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: _responsiveFontSize(14, context),
                  color: Colors.grey[600],
                ),
              ),
              if (_minimizeAttempts > 0) ...[
                SizedBox(height: _responsivePadding(12, context)),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '⚠️ Terdeteksi $_minimizeAttempts percobaan minimize',
                    style: GoogleFonts.poppins(
                      fontSize: _responsiveFontSize(12, context),
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              SizedBox(height: _responsivePadding(24, context)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _exitPressCount = 0;
                          _showExitWarning = false;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: _responsivePadding(12, context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Lanjutkan',
                        style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
                      ),
                    ),
                  ),
                  SizedBox(width: _responsivePadding(12, context)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _disableLockTaskMode();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: _responsivePadding(12, context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Ya, Keluar',
                        style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
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

  void _handleRefresh() {
    HapticFeedback.lightImpact();
    _webViewController.reload();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            SizedBox(width: _responsivePadding(12, context)),
            Text(
              'Memuat ulang halaman...',
              style: GoogleFonts.poppins(fontSize: _responsiveFontSize(12, context)),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.only(
          bottom: 80,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitTimer?.cancel();
    _disableLockTaskMode();
    super.dispose();
  }

  /// ==================== UI BUILD ====================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isLockTaskModeActive) {
          _showMinimizeWarning();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              if (_isLoading)
                LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
                ),
              
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _webViewController),
                    
                    // Exit Warning Overlay
                    if (_showExitWarning)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: EdgeInsets.all(_responsivePadding(16, context)),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange.shade700, Colors.red.shade600],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded, 
                                    color: Colors.white, 
                                    size: _responsiveIconSize(28, context)
                                  ),
                                  SizedBox(width: _responsivePadding(12, context)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'PERINGATAN KELUAR',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: _responsiveFontSize(14, context),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Tekan ${REQUIRED_PRESS_COUNT - _exitPressCount}x lagi dalam ${PRESS_DURATION_SECONDS} detik',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: _responsiveFontSize(12, context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: _responsivePadding(12, context)),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: _exitPressCount / REQUIRED_PRESS_COUNT,
                                  backgroundColor: Colors.white30,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Lock Task Mode Active Indicator
                    if (_isLockTaskModeActive)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'TERKUNCI',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Minimize Attempts Counter
                    if (_minimizeAttempts > 0)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade600,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '$_minimizeAttempts',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              // Bottom Navigation
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _responsivePadding(24, context), 
                      vertical: _responsivePadding(16, context)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: _buildBottomButton(
                            context: context,
                            icon: Icons.refresh_rounded,
                            label: 'Refresh',
                            color: AppColors.primaryGreen,
                            onTap: _handleRefresh,
                          ),
                        ),
                        SizedBox(width: _responsivePadding(16, context)),
                        Expanded(
                          child: _buildBottomButton(
                            context: context,
                            icon: Icons.exit_to_app_rounded,
                            label: 'Keluar',
                            color: Colors.red,
                            onTap: _handleExitPress,
                            showWarning: true,
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
      ),
    );
  }

  Widget _buildBottomButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool showWarning = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: _responsivePadding(14, context)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: _responsiveIconSize(24, context)),
              SizedBox(width: _responsivePadding(8, context)),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: _responsiveFontSize(16, context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showWarning) ...[
                SizedBox(width: _responsivePadding(4, context)),
                Icon(
                  Icons.warning_amber_rounded, 
                  color: Colors.white, 
                  size: _responsiveIconSize(16, context)
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}