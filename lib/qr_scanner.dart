// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:examgo/qr_payload.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';

import 'app_colors.dart';
import 'app_config.dart';
import 'responsive.dart';

// ─────────────────────────────────────────────────────────────────
// ScanResult — wrapper hasil scan yang SELALU bersih (tidak pernah
// berisi raw JSON / payload mentah).
// Pemisah \x00 (null char) dipilih karena tidak mungkin ada di
// judul ujian maupun URL yang valid.
// ─────────────────────────────────────────────────────────────────
class ScanResult {
  final String url;
  final String title;

  const ScanResult({required this.url, required this.title});

  String encode() => '$title\x00$url';

  static ScanResult decode(String raw) {
    final idx = raw.indexOf('\x00');
    if (idx == -1) {
      // Legacy / plain URL tanpa separator
      return ScanResult(url: raw, title: Uri.tryParse(raw)?.host ?? raw);
    }
    return ScanResult(
      url: raw.substring(idx + 1),
      title: raw.substring(0, idx),
    );
  }
}

// ─────────────────────────────────────────────────────────────────

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
  bool _processing = false;
  bool _disposed = false;

  late final AnimationController _lineAnim;
  final ImagePicker _picker = ImagePicker();

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
    _requestPermission();
  }

  @override
  void dispose() {
    _disposed = true;
    _lineAnim.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  // ─── Permission ───────────────────────────────────────────────

  Future<void> _requestPermission() async {
    if (kIsWeb) {
      _setPermission(true);
      return;
    }
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      _setPermission(true);
    } else {
      setState(() => _permissionDenied = true);
    }
  }

  void _setPermission(bool granted) {
    if (!mounted) return;
    setState(() => _hasPermission = granted);
  }

  // ─── Detection ───────────────────────────────────────────────

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

  // Titik masuk TUNGGAL untuk semua raw QR string.
  // TIDAK ADA raw JSON / payload mentah yang boleh keluar dari sini.
  void _handleRaw(String raw) {
    if (_scanned || _disposed) return;
    setState(() => _scanned = true);
    _controller.stop();

    // 1. Coba decode sebagai ExamGO signed QR
    try {
      final payload = QRPayloadService.validate(raw);
      if (payload != null) {
        final title = payload.title.trim().isNotEmpty
            ? payload.title.trim()
            : Uri.tryParse(payload.url)?.host ?? payload.url;
        _popResult(ScanResult(url: payload.url, title: title));
        return;
      }
    } catch (_) {}

    // 2. Plain https/http URL
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      _showPlainUrlDialog(raw);
      return;
    }

    // 3. Tidak valid sama sekali
    _showInvalidDialog();
  }

  // Satu-satunya tempat Navigator.pop dipanggil dengan hasil scan.
  void _popResult(ScanResult result) {
    if (!mounted) return;
    Navigator.of(context).pop(result.encode());
  }

  // ─── Gallery picker ──────────────────────────────────────────

  Future<void> _pickGallery() async {
    if (_processing || _disposed) return;
    setState(() => _processing = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null || _disposed) {
        setState(() => _processing = false);
        return;
      }
      _showLoadingOverlay();
      final BarcodeCapture? result = await _controller.analyzeImage(file.path);
      if (mounted) Navigator.of(context).pop();
      if (result != null && result.barcodes.isNotEmpty) {
        final raw = result.barcodes.first.rawValue ?? '';
        if (raw.isNotEmpty) {
          _handleRaw(raw);
          return;
        }
      }
      _showNoQrDialog();
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      _showSnack('Gagal memproses gambar: $e', isError: true);
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

  // ─── Dialogs ─────────────────────────────────────────────────

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
                  color: Colors.orange.withOpacity(0.1),
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
              SizedBox(height: context.rs(8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(12),
                  vertical: context.rs(8),
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Lanjutkan hanya jika Anda yakin URL ini aman.',
                        style: GoogleFonts.poppins(
                          fontSize: context.rs(11),
                          color: Colors.red.shade700,
                        ),
                      ),
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

  void _resetScan() {
    if (!mounted || _disposed) return;
    setState(() => _scanned = false);
    _controller.start();
  }

  void _toggleFlash() {
    if (_disposed) return;
    _controller.toggleTorch();
    setState(() => _flashOn = !_flashOn);
  }

  void _switchCamera() {
    if (_disposed) return;
    _controller.switchCamera();
  }

  // ─── Build ───────────────────────────────────────────────────

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
            errorBuilder: (ctx, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kamera tidak dapat diakses:\n${error.errorDetails?.message ?? error.errorCode.toString()}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
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
          color: Colors.black.withOpacity(0.7),
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
              ? AppColors.primaryGreen.withOpacity(0.2)
              : Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppColors.primaryGreen
                : Colors.white.withOpacity(0.3),
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
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPermissionView() {
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
                  'Izin Kamera Diperlukan',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(20),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.rs(12)),
                Text(
                  'Aplikasi memerlukan akses kamera untuk memindai QR Code ujian.',
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
                      'Buka Pengaturan',
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

// ─── Scan line ────────────────────────────────────────────────────

class _ScanLine extends StatelessWidget {
  final AnimationController animation;
  const _ScanLine({required this.animation});

  @override
  Widget build(BuildContext context) {
    final scanSize = MediaQuery.of(context).size.width * 0.7;
    final top = (MediaQuery.of(context).size.height - scanSize) / 2;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => Positioned(
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
                color: AppColors.primaryGreen.withOpacity(0.5),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Scanner overlay ──────────────────────────────────────────────

class _ScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.width * 0.7;
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
      Paint()..color = Colors.black.withOpacity(0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(24)),
      Paint()
        ..color = Colors.white.withOpacity(0.4)
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

// ─── Reusable dialog widgets ──────────────────────────────────────

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
                color: iconColor.withOpacity(0.1),
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
