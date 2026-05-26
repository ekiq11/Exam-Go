import 'dart:async';
import 'dart:io' show Platform;
import 'package:examgo/services/qr_payload.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';

import '../constant/app_colors.dart';
import '../constant/responsive.dart';

class ScanResult {
  final String url;
  final String title;
  final String examId;
  const ScanResult({required this.url, required this.title, this.examId = ''});
  String encode() => '$title\x00$url\x00$examId';
  static ScanResult decode(String raw) {
    final parts = raw.split('\x00');
    if (parts.length == 1) {
      return ScanResult(url: raw, title: Uri.tryParse(raw)?.host ?? raw);
    }
    return ScanResult(
      title: parts[0],
      url: parts[1],
      examId: parts.length > 2 ? parts[2] : '',
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  bool _scanned = false;
  bool _flashOn = false;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  bool _processing = false;
  bool _disposed = false;
  // FIX BUG-SCANNER: Flag bahwa camera hardware sudah selesai init.
  // Tombol Flash/Balik/Galeri tidak boleh memanggil controller methods
  // sebelum flag ini true — mencegah MobileScannerException(controllerUninitialized).
  bool _controllerReady = false;
  late final AnimationController _lineAnim;
  final ImagePicker _picker = ImagePicker();

  // ── CameraUnavailableException retry mechanism ─────────────────
  // Beberapa device (Advan, Xiaomi entry-level) melaporkan 0 kamera tersedia
  // saat CameraX init karena HAL issue atau camera service crash sementara.
  // Solusi: auto-retry hingga 3x dengan delay yang meningkat sebelum menyerah.
  static const int _kMaxCameraRetry = 3;
  static const Duration _kRetryBaseDelay = Duration(milliseconds: 1500);
  int _cameraRetryCount = 0;
  Timer? _cameraRetryTimer;
  bool _cameraHardFailed = false; // true setelah semua retry habis
  String _cameraErrorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    // FIX BUG-SCANNER: MobileScannerController extends ValueNotifier<MobileScannerState>.
    // Dengarkan perubahan state untuk mendeteksi kapan camera hardware selesai init.
    // onScannerStarted tidak tersedia di mobile_scanner ^7.1.3 — ini alternatif yang benar.
    _controller.addListener(_onScannerStateChanged);
    // FIX CAMERA-CRASH: Lakukan pre-flight check via native MethodChannel SEBELUM
    // permission diminta dan CameraX diinisialisasi. Ini mencegah crash fatal
    // (RuntimeException dari Java) pada device yang melaporkan 0 kamera (HAL issue).
    _preCheckCamera();
  }

  /// Pre-flight check ketersediaan kamera via native Android MethodChannel.
  /// Dipanggil sebelum _requestPermission() agar CameraX tidak pernah disentuh
  /// jika device benar-benar tidak punya kamera aktif.
  /// Crash pattern: MobileScanner.start$lambda$18 → ExecutionException → 
  /// InitializationException → CameraUnavailableException: Available cameras: 0
  Future<void> _preCheckCamera() async {
    if (!Platform.isAndroid || _disposed) {
      // iOS tidak punya masalah ini; langsung lanjut ke permission check
      _requestPermission();
      return;
    }
    try {
      const nativeChannel = MethodChannel('com.examgo/locktask');
      final result = await nativeChannel
          .invokeMethod<Map<Object?, Object?>>('checkCameraAvailable')
          .timeout(const Duration(seconds: 3));
      final available = (result?['available'] as bool?) ?? true;
      if (!available && mounted) {
        final reason = (result?['reason'] as String?) ?? 'Kamera tidak terdeteksi';
        setState(() {
          _cameraHardFailed = true;
          _cameraErrorMessage = reason;
        });
        return; // STOP — jangan lanjutkan ke permission / scanner init
      }
    } catch (_) {
      // Jika channel error (mis. belum register), lanjut normal —
      // lebih baik coba scanner daripada blokir user secara salah.
    }
    _requestPermission();
  }


  void _onScannerStateChanged() {
    if (!mounted) return;
    final isRunning = _controller.value.isRunning;
    if (_controllerReady != isRunning) {
      // Kamera berhasil start → reset retry counter & hard-fail flag
      if (isRunning && _cameraRetryCount > 0) {
        _cameraRetryCount = 0;
        _cameraHardFailed = false;
      }
      setState(() => _controllerReady = isRunning);
    }
  }

  /// Dipanggil oleh errorBuilder saat MobileScanner melaporkan error kamera.
  /// Untuk CameraUnavailableException (errorCode.cameraError / generic),
  /// coba restart controller dengan delay bertahap (1.5s → 3s → 4.5s).
  void _onCameraError(MobileScannerException error) {
    if (_disposed || !mounted) return;

    final isRetryable = error.errorCode == MobileScannerErrorCode.genericError ||
        error.errorCode == MobileScannerErrorCode.controllerUninitialized ||
        // cameraError enum mungkin tidak ada di semua versi — tangkap semua
        // errorCode yang bukan permission agar retry tetap berjalan.
        error.errorCode != MobileScannerErrorCode.permissionDenied;

    if (!isRetryable || _cameraRetryCount >= _kMaxCameraRetry) {
      // Sudah max retry atau error permanen (permission) → tampilkan hard-fail UI
      setState(() {
        _cameraHardFailed = true;
        _cameraErrorMessage = error.errorDetails?.message ??
            'Kamera tidak dapat diakses setelah $_kMaxCameraRetry percobaan ulang.';
      });
      return;
    }

    _cameraRetryCount++;
    // Delay meningkat setiap retry: 1.5s, 3s, 4.5s (exponential-ish backoff)
    final delay = _kRetryBaseDelay * _cameraRetryCount;

    // Paksa rebuild agar UI retry ditampilkan sebelum timer berjalan
    if (mounted) setState(() {});

    _cameraRetryTimer?.cancel();
    _cameraRetryTimer = Timer(delay, () async {
      // FIX CRASH-4: MobileScannerController.start.<fn> race condition (5 events).
      // Check _disposed sebelum await aman, tapi ada window kecil antara
      // Timer fire dan saat _controller.start() dipanggil di mana widget
      // bisa di-dispose. Guard ganda: cek sebelum DAN setelah start().
      if (_disposed || !mounted) return;
      try {
        await _controller.start();
        // Double-check setelah await — widget bisa saja dispose() selama
        // start() berjalan secara async (terutama di device lambat).
        if (_disposed || !mounted) {
          // Controller sudah distart tapi widget sudah dispose —
          // stop controller agar tidak ada kamera yang terus berjalan.
          try { await _controller.stop(); } catch (_) {}
        }
      } catch (_) {
        // Jika start() throws, errorBuilder akan dipanggil lagi → retry berikutnya.
        // Tidak perlu aksi tambahan — retry sudah terhandle di _onCameraError().
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cameraRetryTimer?.cancel();
    _lineAnim.dispose();
    WidgetsBinding.instance.removeObserver(this);
    // FIX BUG-SCANNER: Hapus listener sebelum dispose controller.
    _controller.removeListener(_onScannerStateChanged);
    _controller.dispose();
    super.dispose();
  }

  // ── Permission ────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    if (kIsWeb) {
      _setPermission(true);
      return;
    }
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      _setPermission(true);
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionDenied = true;
        _permissionPermanentlyDenied = true;
      });
    } else {
      setState(() => _permissionDenied = true);
    }
  }

  void _setPermission(bool v) {
    if (!mounted) return;
    setState(() => _hasPermission = v);
  }

  // Re-check saat kembali dari Settings (iOS & Android)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _permissionDenied &&
        !_hasPermission) {
      _requestPermission();
    }
  }

  // ── Detection ─────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (_scanned || _processing || _disposed) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.isNotEmpty) {
        HapticFeedback.mediumImpact();
        _handleRaw(raw);
        break;
      }
    }
  }

  void _handleRaw(String raw) {
    if (_scanned || _disposed) return;
    setState(() => _scanned = true);
    _controller.stop();
    try {
      final p = QRPayloadService.validate(raw);
      if (p != null) {
        final t = p.title.trim().isNotEmpty
            ? p.title.trim()
            : Uri.tryParse(p.url)?.host ?? p.url;
        _popResult(ScanResult(url: p.url, title: t, examId: p.nonce));
        return;
      }
    } catch (_) {}
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      _showPlainUrlDialog(raw);
      return;
    }
    _showInvalidDialog();
  }

  void _popResult(ScanResult r) {
    if (!mounted) return;
    Navigator.of(context).pop(r.encode());
  }

  // ── Gallery picker ────────────────────────────────────────────

  Future<void> _pickGallery() async {
    // FIX: Guard _controllerReady — analyzeImage() bisa throw jika controller
    // belum init. Berbeda dengan flash/balik, gallery bisa dipakai walau
    // camera live view belum siap (analyzeImage = off-stream processing).
    // Tapi tetap perlu guard _disposed agar tidak crash saat widget sudah mati.
    if (_processing || _disposed) return;
    setState(() => _processing = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null || _disposed) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      _showLoadingOverlay();
      // FIX: Guard _disposed setelah await pickImage — user bisa saja menutup
      // screen saat file picker terbuka, sehingga controller sudah di-dispose.
      if (_disposed) {
        if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
        return;
      }
      final result = await _controller.analyzeImage(file.path);
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      if (!_disposed && result != null && result.barcodes.isNotEmpty) {
        final raw = result.barcodes.first.rawValue ?? '';
        if (raw.isNotEmpty) {
          _handleRaw(raw);
          return;
        }
      }
      if (!_disposed) _showNoQrDialog();
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      if (!_disposed) _showSnack('Gagal memproses gambar: $e', isError: true);
    } finally {
      if (mounted && !_disposed) setState(() => _processing = false);
    }
  }

  void _showLoadingOverlay() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryGreen),
              const SizedBox(height: 16),
              Text(
                'Memproses QR Code…',
                style: GoogleFonts.poppins(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────

  void _showPlainUrlDialog(String url) {
    if (!mounted) return;
    final host = Uri.tryParse(url)?.host ?? url;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(context.rs(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(context.rs(14)),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: context.rs(44),
                  color: Colors.orange,
                ),
              ),
              SizedBox(height: context.rs(14)),
              Text(
                'QR Tidak Terenkripsi',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(16),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.rs(6)),
              Text(
                'QR Code ini bukan dari ExamGO Generator.',
                style: GoogleFonts.poppins(
                  fontSize: context.rs(12),
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: context.rs(14)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(context.rs(12)),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.language,
                          size: 14,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            host,
                            style: GoogleFonts.poppins(
                              fontSize: context.rs(13),
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      url,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(10),
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.rs(22)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _resetScan();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Batal',
                        style: GoogleFonts.poppins(fontSize: context.rs(14)),
                      ),
                    ),
                  ),
                  SizedBox(width: context.rs(10)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _popResult(ScanResult(url: url, title: host));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: EdgeInsets.symmetric(vertical: context.rs(12)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Lanjutkan',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(14),
                          color: Colors.white,
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

  void _showInvalidDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _BaseDialog(
        icon: Icons.qr_code_scanner,
        iconColor: Colors.red,
        title: 'QR Tidak Valid',
        body: 'QR Code ini bukan QR ujian ExamGO yang valid.',
        actions: [
          _DialogBtn(
            label: 'Coba Lagi',
            bgColor: AppColors.primaryGreen,
            onTap: () {
              Navigator.of(ctx).pop();
              _resetScan();
            },
          ),
        ],
      ),
    );
  }

  void _showNoQrDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _BaseDialog(
        icon: Icons.image_search,
        iconColor: Colors.orange,
        title: 'QR Tidak Ditemukan',
        body: 'Pastikan gambar mengandung QR Code yang jelas.',
        actions: [
          _DialogBtn(
            label: 'Batal',
            outlined: true,
            onTap: () => Navigator.of(ctx).pop(),
          ),
          _DialogBtn(
            label: 'Coba Lagi',
            bgColor: AppColors.primaryGreen,
            onTap: () {
              Navigator.of(ctx).pop();
              _pickGallery();
            },
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _resetScan() async {
    if (!mounted || _disposed) return;
    // FIX CRASH-3: MobileScannerController._throwIfNotInitialized (6 events).
    // _controller.start() sebelumnya dipanggil tanpa await dan tanpa try-catch.
    // Jika controller sedang dalam state transisi (mis. sedang stop/restart),
    // _throwIfNotInitialized akan dilempar sebagai MobileScannerException
    // yang langsung crash karena tidak ada error handler.
    //
    // Fix: (1) gunakan async/await, (2) wrap dalam try-catch, (3) reset
    // _controllerReady SEBELUM start() agar guard flash/balik tetap aktif.
    setState(() {
      _scanned = false;
      _controllerReady = false;
    });
    try {
      await _controller.start();
    } catch (_) {
      // Jika start() gagal, errorBuilder MobileScanner akan dipanggil
      // dan _onCameraError() akan menangani retry — tidak perlu aksi di sini.
    }
  }

  void _toggleFlash() {
    // FIX BUG-SCANNER: Guard _controllerReady agar tidak crash sebelum camera init.
    if (_disposed || !_controllerReady) return;
    _controller.toggleTorch();
    setState(() => _flashOn = !_flashOn);
  }

  void _switchCamera() {
    // FIX BUG-SCANNER: Guard _controllerReady agar tidak crash sebelum camera init.
    if (_disposed || !_controllerReady) return;
    _controller.switchCamera();
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission && !kIsWeb) return _buildPermissionView();
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _circleBtn(
          icon: Icons.close,
          onTap: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Scan QR Ujian',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: context.rs(16),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // _controllerReady dikelola oleh _onScannerStateChanged() via controller.addListener().
            // Tidak perlu onScannerStarted (tidak ada di mobile_scanner ^7.1.3).
            errorBuilder: (ctx, error) {
              // Picu retry mechanism — fire-and-forget, tidak tunggu hasil
              // Gunakan addPostFrameCallback agar tidak setState() di tengah build
              if (!_cameraHardFailed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _onCameraError(error);
                });
              }
              return _cameraHardFailed
                  ? _buildCameraErrorView()
                  : _buildCameraRetryView(error);
            },
          ),
          CustomPaint(
            painter: _ScannerOverlay(),
            child: const SizedBox.expand(),
          ),
          _ScanLine(animation: _lineAnim),
          _buildInstruction(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildInstruction() {
    return Positioned(
      bottom: context.rs(160),
      left: context.rs(32),
      right: context.rs(32),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.rs(20),
          vertical: context.rs(14),
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.qr_code_scanner,
              color: AppColors.primaryGreen,
              size: context.rs(22),
            ),
            SizedBox(width: context.rs(10)),
            Expanded(
              child: Text(
                'Arahkan kamera ke QR Code ujian',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: context.rs(13),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: context.rs(36),
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlBtn(
            icon: _flashOn ? Icons.flash_on : Icons.flash_off,
            label: 'Flash',
            isActive: _flashOn,
            onTap: _toggleFlash,
          ),
          _controlBtn(
            icon: Icons.photo_library,
            label: 'Galeri',
            onTap: _pickGallery,
          ),
          _controlBtn(
            icon: Icons.flip_camera_ios,
            label: 'Balik',
            onTap: _switchCamera,
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.rs(18),
          vertical: context.rs(11),
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryGreen.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppColors.primaryGreen
                : Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primaryGreen : Colors.white,
              size: context.rs(22),
            ),
            SizedBox(height: context.rs(4)),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: context.rs(11),
                color: isActive ? AppColors.primaryGreen : Colors.white,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }

  // ── Camera Error Widgets ───────────────────────────────────────

  /// UI saat kamera sedang dalam proses retry (transient error).
  /// Tampilkan animasi loading dan informasi percobaan ke-N dari total retry.
  Widget _buildCameraRetryView(MobileScannerException error) {
    final attempt = _cameraRetryCount;
    final delayMs = (_kRetryBaseDelay.inMilliseconds * (attempt + 1));
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                attempt == 0
                    ? 'Menginisialisasi kamera…'
                    : 'Mencoba ulang kamera (${attempt + 1}/$_kMaxCameraRetry)…',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: context.rs(14),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                attempt > 0
                    ? 'Menunggu ${delayMs ~/ 1000} detik sebelum mencoba lagi…'
                    : 'Harap tunggu sebentar',
                style: GoogleFonts.poppins(
                  color: Colors.white60,
                  fontSize: context.rs(12),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI hard-fail setelah semua retry habis ATAU device tidak punya kamera.
  /// Berikan opsi galeri sebagai fallback agar user tetap bisa scan QR via gambar.
  Widget _buildCameraErrorView() {
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(context.rs(28)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(context.rs(18)),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.shade600,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.no_photography_rounded,
                    color: Colors.red.shade400,
                    size: context.rs(44),
                  ),
                ),
                SizedBox(height: context.rs(20)),
                Text(
                  'Kamera Tidak Tersedia',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: context.rs(18),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.rs(10)),
                Text(
                  _cameraErrorMessage.isNotEmpty
                      ? _cameraErrorMessage
                      : 'Kamera tidak dapat diakses. Kemungkinan sedang digunakan aplikasi lain atau terjadi kesalahan sistem.',
                  style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: context.rs(13),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.rs(16)),
                // Tip: saran troubleshooting
                Container(
                  padding: EdgeInsets.all(context.rs(12)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: Colors.amber.shade400,
                        size: context.rs(18),
                      ),
                      SizedBox(width: context.rs(10)),
                      Expanded(
                        child: Text(
                          'Coba tutup semua aplikasi kamera lain, lalu restart HP. Atau gunakan pilihan Galeri di bawah untuk upload foto QR Code.',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: context.rs(12),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.rs(24)),
                // Tombol Galeri sebagai fallback utama
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _processing ? null : _pickGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    label: Text(
                      'Pilih QR dari Galeri',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(14),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: context.rs(14)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: context.rs(12)),
                // Tombol Tutup
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    label: Text(
                      'Kembali',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(14),
                        color: Colors.white60,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: EdgeInsets.symmetric(vertical: context.rs(14)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionView() {
    final isIOS = !kIsWeb && Platform.isIOS;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(context.rs(32)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt_rounded,
                  size: context.rs(80),
                  color: Colors.grey.shade400,
                ),
                SizedBox(height: context.rs(24)),
                Text(
                  _permissionPermanentlyDenied
                      ? 'Akses Kamera Diblokir'
                      : 'Izin Kamera Diperlukan',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(20),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.rs(12)),
                Text(
                  _permissionPermanentlyDenied && isIOS
                      ? 'Buka Pengaturan → ExamGO → Kamera, lalu aktifkan izin kamera.'
                      : _permissionPermanentlyDenied
                      ? 'Buka Pengaturan → Aplikasi → ExamGO → Izin → Kamera, lalu aktifkan.'
                      : 'Aplikasi memerlukan akses kamera untuk memindai QR Code ujian.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(14),
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: context.rs(32)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async => openAppSettings(),
                    icon: const Icon(Icons.settings),
                    label: Text(
                      isIOS ? 'Buka Pengaturan iPhone' : 'Buka Pengaturan',
                      style: GoogleFonts.poppins(fontSize: context.rs(15)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      padding: EdgeInsets.symmetric(vertical: context.rs(14)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: context.rs(12)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickGallery,
                    icon: const Icon(Icons.photo_library),
                    label: Text(
                      'Pilih dari Galeri',
                      style: GoogleFonts.poppins(fontSize: context.rs(15)),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      padding: EdgeInsets.symmetric(vertical: context.rs(14)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
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

// ─── Scan line ─────────────────────────────────────────────────────

class _ScanLine extends StatelessWidget {
  final AnimationController animation;
  const _ScanLine({required this.animation});
  @override
  Widget build(BuildContext context) {
    final scanSize = MediaQuery.of(context).size.shortestSide * 0.7;
    final top = (MediaQuery.of(context).size.height - scanSize) / 2;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Positioned(
        left: (MediaQuery.of(context).size.width - scanSize) / 2,
        top: top + scanSize * animation.value,
        child: Container(
          width: scanSize,
          height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.primaryGreen,
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner overlay ───────────────────────────────────────────────

class _ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Gunakan shortestSide × 0.7 agar pas di tablet/landscape
    final scanSize = size.shortestSide * 0.7;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanSize,
      height: scanSize,
    );
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(24)))
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(24)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final cLen = scanSize * 0.12;
    final cp = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    void corner(Offset h1, Offset h2, Offset v1, Offset v2) {
      canvas.drawLine(h1, h2, cp);
      canvas.drawLine(v1, v2, cp);
    }

    corner(
      scanRect.topLeft + Offset(22, 0),
      scanRect.topLeft + Offset(22 + cLen, 0),
      scanRect.topLeft + Offset(0, 22),
      scanRect.topLeft + Offset(0, 22 + cLen),
    );
    corner(
      scanRect.topRight + Offset(-22, 0),
      scanRect.topRight + Offset(-22 - cLen, 0),
      scanRect.topRight + Offset(0, 22),
      scanRect.topRight + Offset(0, 22 + cLen),
    );
    corner(
      scanRect.bottomLeft + Offset(22, 0),
      scanRect.bottomLeft + Offset(22 + cLen, 0),
      scanRect.bottomLeft + Offset(0, -22),
      scanRect.bottomLeft + Offset(0, -22 - cLen),
    );
    corner(
      scanRect.bottomRight + Offset(-22, 0),
      scanRect.bottomRight + Offset(-22 - cLen, 0),
      scanRect.bottomRight + Offset(0, -22),
      scanRect.bottomRight + Offset(0, -22 - cLen),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Reusable dialog widgets ────────────────────────────────────────

class _BaseDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final List<Widget> actions;
  const _BaseDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.all(context.rs(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(context.rs(14)),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: context.rs(44), color: iconColor),
            ),
            SizedBox(height: context.rs(14)),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: context.rs(16),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.rs(10)),
            Text(
              body,
              style: GoogleFonts.poppins(
                fontSize: context.rs(13),
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.rs(22)),
            Row(
              children:
                  actions.expand((w) => [w, const SizedBox(width: 10)]).toList()
                    ..removeLast(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? bgColor;
  final bool outlined;
  const _DialogBtn({
    required this.label,
    required this.onTap,
    this.bgColor,
    this.outlined = false,
  });
  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return Expanded(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: context.rs(12)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(fontSize: context.rs(14)),
          ),
        ),
      );
    }
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor ?? AppColors.primaryGreen,
          padding: EdgeInsets.symmetric(vertical: context.rs(12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: context.rs(14),
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
