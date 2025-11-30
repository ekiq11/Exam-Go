// // ignore_for_file: deprecated_member_use

// import 'dart:async';
// import 'package:examgo/app_colors.dart';
// import 'package:examgo/security_service.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_fonts/google_fonts.dart';
// import 'package:mobile_scanner/mobile_scanner.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:webview_flutter/webview_flutter.dart';

// // ===== FUNGSI BANTU RESPONSIF (KONSISTEN DENGAN FILE SEBELUMNYA) =====
// double _responsiveFontSize(double baseSize, BuildContext context) {
//   final shortestSide = MediaQuery.of(context).size.shortestSide;
//   final scale = (shortestSide / 360.0).clamp(0.85, 1.25);
//   return baseSize * scale;
// }

// double _responsivePadding(double baseValue, BuildContext context) {
//   return _responsiveFontSize(baseValue, context);
// }

// double _responsiveIconSize(double baseSize, BuildContext context) {
//   return _responsiveFontSize(baseSize, context);
// }

// // ===================================================================

// class QRScannerScreen extends StatefulWidget {
//   const QRScannerScreen({super.key});

//   @override
//   State<QRScannerScreen> createState() => _QRScannerScreenState();
// }

// class _QRScannerScreenState extends State<QRScannerScreen> with WidgetsBindingObserver {
//   MobileScannerController? _cameraController;
//   bool _isScanned = false;
//   bool _isFlashOn = false;
//   bool _hasPermission = false;
//   bool _permissionDenied = false;
//   String _scannedData = '';

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _requestCameraPermission();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) {
//       if (!_hasPermission && !_permissionDenied) {
//         _requestCameraPermission();
//       }
//     }
//   }

//   Future<void> _requestCameraPermission() async {
//     if (kIsWeb) {
//       if (mounted) {
//         setState(() {
//           _hasPermission = true;
//         });
//       }
//       _initializeCamera();
//       return;
//     }

//     final status = await Permission.camera.request();
//     final hasPermission = status.isGranted;
//     final isDenied = status.isDenied || status.isPermanentlyDenied;

//     if (mounted) {
//       setState(() {
//         _hasPermission = hasPermission;
//         _permissionDenied = isDenied;
//       });

//       if (hasPermission) {
//         _initializeCamera();
//       } else if (isDenied) {
//         _showPermissionDialog();
//       }
//     }
//   }

//   void _initializeCamera() {
//     if (_cameraController != null) return;

//     _cameraController = MobileScannerController(
//       detectionSpeed: DetectionSpeed.normal,
//       facing: CameraFacing.back,
//       torchEnabled: false,
//     );
//   }

//   void _showPermissionDialog() {
//     if (!mounted) return;
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         title: Row(
//           children: [
//             Icon(Icons.warning, color: AppColors.warning, size: _responsiveIconSize(20, context)),
//             SizedBox(width: _responsivePadding(8, context)),
//             Expanded(
//               child: Text(
//                 'Izin Kamera Diperlukan',
//                 style: GoogleFonts.poppins(
//                   fontWeight: FontWeight.bold,
//                   fontSize: _responsiveFontSize(16, context),
//                 ),
//               ),
//             ),
//           ],
//         ),
//         content: Text(
//           'Aplikasi memerlukan akses kamera untuk memindai QR Code. Silakan aktifkan izin kamera di pengaturan.',
//           style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//               Navigator.of(context).pop();
//             },
//             child: Text('Batal', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//           ElevatedButton(
//             onPressed: () async {
//               Navigator.of(context).pop();
//               await openAppSettings();
//             },
//             style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.primaryGreen,
//               padding: EdgeInsets.symmetric(vertical: _responsivePadding(12, context)),
//             ),
//             child: Text('Buka Pengaturan', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//         ],
//       ),
//     );
//   }

//   void _onDetect(BarcodeCapture capture) {
//     if (_isScanned || _cameraController == null) return;

//     final List<Barcode> barcodes = capture.barcodes;
//     for (final barcode in barcodes) {
//       if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
//         final data = barcode.rawValue!;
//         setState(() {
//           _isScanned = true;
//           _scannedData = data;
//         });

//         _cameraController!.stop();

//         if (_isValidUrl(data)) {
//           _openExamWithSecurity(data);
//         } else {
//           _showSuccessDialog(data);
//         }
//         break;
//       }
//     }
//   }

//   bool _isValidUrl(String text) {
//     if (text.startsWith('http://') || text.startsWith('https://')) return true;
//     final urlPattern = RegExp(
//       r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$',
//     );
//     return urlPattern.hasMatch(text);
//   }

//   Future<void> _openExamWithSecurity(String url) async {
//     if (url.isEmpty) return;

//     String finalUrl = url;
//     if (!url.startsWith('http://') && !url.startsWith('https://')) {
//       finalUrl = 'https://$url';
//     }

//     try {
//       final uri = Uri.parse(finalUrl);
//       if (!mounted) return;
//       await Navigator.of(context).pushReplacement(
//         MaterialPageRoute(
//           builder: (context) => QRWebViewScreen(url: finalUrl),
//         ),
//       );
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('URL tidak valid: $e')),
//         );
//       }
//     }
//   }

//   void _showSuccessDialog(String data) {
//     if (!mounted) return;
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         title: Row(
//           children: [
//             Container(
//               padding: EdgeInsets.all(_responsivePadding(8, context)),
//               decoration: BoxDecoration(
//                 color: AppColors.success,
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 Icons.check,
//                 color: Colors.white,
//                 size: _responsiveIconSize(24, context),
//               ),
//             ),
//             SizedBox(width: _responsivePadding(12, context)),
//             Expanded(
//               child: Text(
//                 'QR Code Terdeteksi',
//                 style: GoogleFonts.poppins(
//                   fontWeight: FontWeight.bold,
//                   fontSize: _responsiveFontSize(16, context),
//                 ),
//               ),
//             ),
//           ],
//         ),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Container(
//               padding: EdgeInsets.all(_responsivePadding(12, context)),
//               decoration: BoxDecoration(
//                 color: AppColors.paleGreen,
//                 borderRadius: BorderRadius.circular(_responsivePadding(8, context)),
//               ),
//               child: SelectableText(
//                 data,
//                 style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//               ),
//             ),
//             SizedBox(height: _responsivePadding(8, context)),
//             Text(
//               'Data ini bukan URL yang valid',
//               style: GoogleFonts.poppins(
//                 fontSize: _responsiveFontSize(12, context),
//                 color: AppColors.textSecondary,
//               ),
//             ),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//               Navigator.of(context).pop();
//             },
//             child: Text('Batal', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//               Navigator.of(context).pop(data);
//             },
//             style: ElevatedButton.styleFrom(
//               backgroundColor: AppColors.primaryGreen,
//               padding: EdgeInsets.symmetric(vertical: _responsivePadding(12, context)),
//             ),
//             child: Text('Lanjutkan', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//         ],
//       ),
//     );
//   }

//   void _toggleFlash() {
//     if (_cameraController == null) return;
//     _cameraController!.toggleTorch();
//     setState(() {
//       _isFlashOn = !_isFlashOn;
//     });
//   }

//   void _switchCamera() {
//     if (_cameraController == null) return;
//     _cameraController!.switchCamera();
//   }

//   void _resetScanner() {
//     if (_cameraController == null) return;
//     setState(() {
//       _isScanned = false;
//       _scannedData = '';
//     });
//     _cameraController!.start();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _cameraController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (!_hasPermission) {
//       if (_permissionDenied) {
//         return Scaffold(
//           body: SafeArea(
//             child: Center(
//               child: Padding(
//                 padding: EdgeInsets.symmetric(horizontal: _responsivePadding(32, context)),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.camera_alt_rounded,
//                       size: _responsiveIconSize(64, context),
//                       color: AppColors.error,
//                     ),
//                     SizedBox(height: _responsivePadding(16, context)),
//                     Text(
//                       'Izin Kamera Ditolak',
//                       style: GoogleFonts.poppins(
//                         fontSize: _responsiveFontSize(18, context),
//                         fontWeight: FontWeight.bold,
//                         color: AppColors.textPrimary,
//                       ),
//                     ),
//                     SizedBox(height: _responsivePadding(12, context)),
//                     Text(
//                       'Aplikasi memerlukan akses kamera untuk memindai QR Code. Silakan izinkan di pengaturan.',
//                       textAlign: TextAlign.center,
//                       style: GoogleFonts.poppins(
//                         fontSize: _responsiveFontSize(14, context),
//                         color: AppColors.textSecondary,
//                       ),
//                     ),
//                     SizedBox(height: _responsivePadding(32, context)),
//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton(
//                         onPressed: () async {
//                           await openAppSettings();
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: AppColors.primaryGreen,
//                           padding: EdgeInsets.symmetric(vertical: _responsivePadding(14, context)),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
//                           ),
//                         ),
//                         child: Text(
//                           'Buka Pengaturan',
//                           style: GoogleFonts.poppins(
//                             fontSize: _responsiveFontSize(16, context),
//                             color: Colors.white,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         );
//       } else {
//         return Scaffold(
//           body: SafeArea(
//             child: Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   const CircularProgressIndicator.adaptive(),
//                   SizedBox(height: _responsivePadding(16, context)),
//                   Text(
//                     'Meminta akses kamera...',
//                     style: GoogleFonts.poppins(fontSize: _responsiveFontSize(16, context)),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       }
//     }

//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             _buildHeader(),
//             Expanded(
//               child: Stack(
//                 children: [
//                   MobileScanner(
//                     controller: _cameraController!,
//                     onDetect: _onDetect,
//                   ),
//                   CustomPaint(
//                     painter: ScannerOverlay(responsive: true, context: context),
//                     child: Container(),
//                   ),
//                   Positioned(
//                     bottom: _responsivePadding(120, context),
//                     left: 0,
//                     right: 0,
//                     child: Container(
//                       margin: EdgeInsets.symmetric(horizontal: _responsivePadding(32, context)),
//                       padding: EdgeInsets.all(_responsivePadding(16, context)),
//                       decoration: BoxDecoration(
//                         color: Colors.black.withOpacity(0.7),
//                         borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
//                       ),
//                       child: Text(
//                         'Arahkan kamera ke QR Code untuk memulai ujian',
//                         textAlign: TextAlign.center,
//                         style: GoogleFonts.poppins(
//                           color: Colors.white,
//                           fontSize: _responsiveFontSize(14, context),
//                           fontWeight: FontWeight.w500,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             _buildControlBar(),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildHeader() {
//     return Container(
//       padding: EdgeInsets.symmetric(
//         horizontal: _responsivePadding(16, context),
//         vertical: _responsivePadding(12, context),
//       ),
//       decoration: BoxDecoration(
//         color: AppColors.primaryGreen,
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.1),
//             blurRadius: 4,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           IconButton(
//             icon: Icon(Icons.arrow_back, color: Colors.white, size: _responsiveIconSize(24, context)),
//             onPressed: () => Navigator.of(context).pop(),
//           ),
//           SizedBox(width: _responsivePadding(8, context)),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Scan QR Code',
//                   style: GoogleFonts.poppins(
//                     fontSize: _responsiveFontSize(16, context),
//                     fontWeight: FontWeight.w600,
//                     color: Colors.white,
//                   ),
//                 ),
//                 Text(
//                   'Pindai QR Code untuk memulai',
//                   style: GoogleFonts.poppins(
//                     fontSize: _responsiveFontSize(11, context),
//                     color: Colors.white.withOpacity(0.8),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildControlBar() {
//     return Container(
//       padding: EdgeInsets.all(_responsivePadding(16, context)),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 10,
//             offset: const Offset(0, -2),
//           ),
//         ],
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//         children: [
//           _buildControlButton(
//             _isFlashOn ? Icons.flash_on : Icons.flash_off,
//             'Flash',
//             _toggleFlash,
//             color: _isFlashOn ? AppColors.warning : AppColors.textSecondary,
//           ),
//           _buildControlButton(
//             Icons.flip_camera_ios,
//             'Ganti',
//             _switchCamera,
//           ),
//           if (_isScanned)
//             _buildControlButton(
//               Icons.refresh,
//               'Scan Ulang',
//               _resetScanner,
//               color: AppColors.primaryGreen,
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildControlButton(
//     IconData icon,
//     String label,
//     VoidCallback onTap, {
//     Color? color,
//   }) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(_responsivePadding(12, context)),
//       child: Container(
//         padding: EdgeInsets.symmetric(
//           horizontal: _responsivePadding(20, context),
//           vertical: _responsivePadding(8, context),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(
//               icon,
//               color: color ?? AppColors.primaryGreen,
//               size: _responsiveIconSize(28, context),
//             ),
//             SizedBox(height: _responsivePadding(4, context)),
//             Text(
//               label,
//               style: GoogleFonts.poppins(
//                 fontSize: _responsiveFontSize(11, context),
//                 color: color ?? AppColors.textPrimary,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class ScannerOverlay extends CustomPainter {
//   final bool responsive;
//   final BuildContext? context;

//   ScannerOverlay({this.responsive = false, this.context});

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = Colors.black.withOpacity(0.6)
//       ..style = PaintingStyle.fill;

//     double scanSize = 280;
//     if (responsive && context != null) {
//       final shortest = MediaQuery.of(context!).size.shortestSide;
//       scanSize = (shortest * 0.7).clamp(240.0, 320.0);
//     }

//     final scanArea = Rect.fromCenter(
//       center: Offset(size.width / 2, size.height / 2),
//       width: scanSize,
//       height: scanSize,
//     );

//     final path = Path()
//       ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
//       ..addRRect(RRect.fromRectAndRadius(scanArea, Radius.circular(scanSize * 0.06)))
//       ..fillType = PathFillType.evenOdd;

//     canvas.drawPath(path, paint);

//     final borderPaint = Paint()
//       ..color = const Color(0xFF2ECC71)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = responsive && context != null
//           ? _responsiveFontSize(3, context!)
//           : 3;

//     canvas.drawRRect(
//       RRect.fromRectAndRadius(scanArea, Radius.circular(scanSize * 0.06)),
//       borderPaint,
//     );

//     final cornerPaint = Paint()
//       ..color = const Color(0xFF2ECC71)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = responsive && context != null
//           ? _responsiveFontSize(6, context!)
//           : 6
//       ..strokeCap = StrokeCap.round;

//     final cornerLength = scanSize * 0.14;

//     void drawCorner(Offset start, Offset end1, Offset end2) {
//       canvas.drawLine(start, end1, cornerPaint);
//       canvas.drawLine(start, end2, cornerPaint);
//     }

//     drawCorner(
//       scanArea.topLeft,
//       scanArea.topLeft + Offset(cornerLength, 0),
//       scanArea.topLeft + Offset(0, cornerLength),
//     );
//     drawCorner(
//       scanArea.topRight,
//       scanArea.topRight - Offset(cornerLength, 0),
//       scanArea.topRight + Offset(0, cornerLength),
//     );
//     drawCorner(
//       scanArea.bottomLeft,
//       scanArea.bottomLeft + Offset(cornerLength, 0),
//       scanArea.bottomLeft - Offset(0, cornerLength),
//     );
//     drawCorner(
//       scanArea.bottomRight,
//       scanArea.bottomRight - Offset(cornerLength, 0),
//       scanArea.bottomRight - Offset(0, cornerLength),
//     );
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }

// // =================== QRWebViewScreen ===================

// class QRWebViewScreen extends StatefulWidget {
//   final String url;

//   const QRWebViewScreen({super.key, required this.url});

//   @override
//   State<QRWebViewScreen> createState() => _QRWebViewScreenState();
// }

// class _QRWebViewScreenState extends State<QRWebViewScreen> {
//   late final WebViewController _webViewController;
//   bool _isLoading = true;
//   String _currentUrl = '';
//   double _loadingProgress = 0.0;
//   Timer? _monitoringTimer;
//   String? _blockedAppDetected;
//   bool _isDialogShown = false;

//   @override
//   void initState() {
//     super.initState();
//     _currentUrl = widget.url;
//     _initializeWebView();
//     _initializeSecurity();
//   }

//   Future<void> _initializeSecurity() async {
//     final securityManager = SecurityManager();
//     final hasPermission = await securityManager.checkAppUsagePermission();

//     if (hasPermission) {
//       final enabled = await securityManager.enableSecureMode();
//       if (enabled) {
//         _startMonitoring();
//       }
//     } else {
//       _showPermissionRequiredDialog();
//     }
//   }

//   void _showPermissionRequiredDialog() {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (!mounted) return;

//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (context) => AlertDialog(
//           title: Text(
//             'Izin Akses Diperlukan',
//             style: GoogleFonts.poppins(fontSize: _responsiveFontSize(16, context), fontWeight: FontWeight.bold),
//           ),
//           content: Text(
//             'Untuk menjaga keamanan ujian, aktifkan "Akses Penggunaan Aplikasi" di pengaturan.\n\n'
//             'Tanpa izin ini, sistem tidak dapat mendeteksi aplikasi seperti WhatsApp atau Chrome.',
//             style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 Navigator.of(context).pop();
//                 Navigator.of(context).pop();
//               },
//               child: Text('Batalkan Ujian', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 Navigator.of(context).pop();
//                 await SecurityManager().openUsageAccessSettings();
//               },
//               style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
//               child: Text('Buka Pengaturan', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//             ),
//           ],
//         ),
//       );
//     });
//   }

//   void _startMonitoring() {
//     _monitoringTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
//       final securityManager = SecurityManager();
//       final blockedApp = await securityManager.checkBlockedApps();

//       if (blockedApp != null) {
//         setState(() {
//           _blockedAppDetected = blockedApp;
//         });
//         _showBlockedAppAndExit(blockedApp);
//       } else {
//         if (_blockedAppDetected != null) {
//           setState(() {
//             _blockedAppDetected = null;
//           });
//         }
//       }
//     });
//   }

//   void _showBlockedAppAndExit(String appName) {
//     if (mounted && !_isDialogShown) {
//       _isDialogShown = true;
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (context) => AlertDialog(
//           title: Text(
//             'UJIAN DIBATALKAN!',
//             style: GoogleFonts.poppins(
//               fontWeight: FontWeight.bold,
//               fontSize: _responsiveFontSize(18, context),
//               color: AppColors.error,
//             ),
//           ),
//           content: Text(
//             'Aplikasi "$appName" terdeteksi.\nUjian dihentikan demi keamanan.',
//             style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//           ),
//           actions: [
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.of(context).pop();
//                 Navigator.of(context).pop();
//                 _isDialogShown = false;
//               },
//               style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
//               child: Text('Mengerti', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//             ),
//           ],
//         ),
//       );
//     }
//   }

//   void _initializeWebView() {
//     _webViewController = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..setNavigationDelegate(
//         NavigationDelegate(
//           onProgress: (progress) {
//             setState(() => _loadingProgress = progress / 100);
//           },
//           onPageStarted: (url) {
//             setState(() {
//               _isLoading = true;
//               _currentUrl = url;
//             });
//           },
//           onPageFinished: (_) {
//             setState(() => _isLoading = false);
//           },
//           onWebResourceError: (error) {
//             _showErrorDialog(error.description ?? 'Terjadi kesalahan jaringan.');
//           },
//         ),
//       )
//       ..loadRequest(Uri.parse(widget.url));
//   }

//   void _showErrorDialog(String message) {
//     if (!mounted) return;
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Row(
//           children: [
//             Icon(Icons.error_outline, color: AppColors.error, size: _responsiveIconSize(20, context)),
//             SizedBox(width: _responsivePadding(8, context)),
//             Text(
//               'Error Memuat Halaman',
//               style: GoogleFonts.poppins(fontSize: _responsiveFontSize(16, context), fontWeight: FontWeight.bold),
//             ),
//           ],
//         ),
//         content: Text(message, style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//         actions: [
//           TextButton(
//             onPressed: Navigator.of(context).pop,
//             child: Text('Tutup', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//               _webViewController.reload();
//             },
//             style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
//             child: Text('Muat Ulang', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _monitoringTimer?.cancel();
//     _disableSecureMode();
//     super.dispose();
//   }

//   Future<void> _disableSecureMode() async {
//     try {
//       final securityManager = SecurityManager();
//       await securityManager.disableSecureMode();
//     } catch (e) {
//       print('Error disabling secure mode: $e');
//     }
//   }

//   void _showExitConfirmation() {
//     if (!mounted) return;
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Keluar Ujian?', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(16, context))),
//         content: Text(
//           'Anda yakin ingin keluar dari ujian? Data yang belum disimpan akan hilang.',
//           style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(),
//             child: Text('Lanjutkan Ujian', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//               Navigator.of(context).pop();
//             },
//             style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
//             child: Text('Keluar', style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context))),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return WillPopScope(
//       onWillPop: () async {
//         _showExitConfirmation();
//         return false;
//       },
//       child: Scaffold(
//         appBar: AppBar(
//           backgroundColor: AppColors.primaryGreen,
//           automaticallyImplyLeading: false,
//           title: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Exam Go',
//                 style: GoogleFonts.poppins(
//                   fontSize: _responsiveFontSize(16, context),
//                   fontWeight: FontWeight.w600,
//                   color: Colors.white,
//                 ),
//               ),
//               Text(
//                 _currentUrl.length > 30
//                     ? '${_currentUrl.substring(0, 30)}...'
//                     : _currentUrl,
//                 style: GoogleFonts.poppins(
//                   fontSize: _responsiveFontSize(10, context),
//                   color: Colors.white.withOpacity(0.8),
//                 ),
//               ),
//             ],
//           ),
//           actions: [
//             IconButton(
//               icon: Icon(Icons.refresh, color: Colors.white, size: _responsiveIconSize(24, context)),
//               onPressed: () => _webViewController.reload(),
//             ),
//           ],
//         ),
//         body: Stack(
//           children: [
//             WebViewWidget(controller: _webViewController),
//             if (_isLoading)
//               LinearProgressIndicator(
//                 value: _loadingProgress,
//                 backgroundColor: Colors.grey[200],
//                 valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGreen),
//               ),
//             if (_blockedAppDetected != null)
//               Container(
//                 color: Colors.black.withOpacity(0.3),
//                 child: Center(
//                   child: Card(
//                     margin: EdgeInsets.all(_responsivePadding(24, context)),
//                     child: Padding(
//                       padding: EdgeInsets.all(_responsivePadding(16, context)),
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Icon(Icons.warning, color: AppColors.warning, size: _responsiveIconSize(48, context)),
//                           SizedBox(height: _responsivePadding(12, context)),
//                           Text(
//                             'Aplikasi Terblokir Terdeteksi',
//                             style: GoogleFonts.poppins(
//                               fontWeight: FontWeight.bold,
//                               fontSize: _responsiveFontSize(16, context),
//                             ),
//                           ),
//                           SizedBox(height: _responsivePadding(8, context)),
//                           Text(
//                             'Tutup aplikasi "$_blockedAppDetected" untuk melanjutkan ujian',
//                             textAlign: TextAlign.center,
//                             style: GoogleFonts.poppins(fontSize: _responsiveFontSize(14, context)),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';
import 'package:examgo/app_colors.dart';
import 'package:examgo/security_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'qris_web_view.dart';

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

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> 
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  bool _isScanned = false;
  bool _isFlashOn = false;
  bool _hasPermission = false;
  bool _permissionDenied = false;
  String _scannedData = '';
  final ImagePicker _imagePicker = ImagePicker();
  
  late AnimationController _animationController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestCameraPermission();
    
    // Animasi scan line
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() => _hasPermission = true);
      }
      _initializeCamera();
      return;
    }

    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
        _permissionDenied = status.isDenied || status.isPermanentlyDenied;
      });

      if (_hasPermission) {
        _initializeCamera();
      } else if (_permissionDenied) {
        _showPermissionDialog();
      }
    }
  }

  void _initializeCamera() {
    if (_cameraController != null) return;
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _showPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.camera_alt, size: 48, color: Colors.orange),
              ),
              SizedBox(height: 20),
              Text(
                'Izin Kamera Diperlukan',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Aplikasi memerlukan akses kamera untuk memindai QR Code ujian',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Batal'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openAppSettings();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Buka Pengaturan'),
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

  /// Request storage permission berdasarkan versi Android
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;
    
    if (!Platform.isAndroid) {
      // iOS menggunakan photos permission
      final status = await Permission.photos.request();
      return status.isGranted;
    }

    // Android: Cek versi SDK
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 33) {
      // Android 13+ (API 33+): Tidak perlu izin storage untuk pick image
      // ImagePicker sudah handle sendiri dengan Photo Picker API
      return true;
    } else {
      // Android 12 ke bawah: Gunakan storage permission
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      if (!kIsWeb) {
        final hasPermission = await _requestStoragePermission();
        
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(child: Text('Izin akses galeri diperlukan')),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                action: SnackBarAction(
                  label: 'Pengaturan',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return;
        }
      }

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.primaryGreen),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Memproses QR Code...',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final result = await _cameraController?.analyzeImage(image.path);

      if (mounted) Navigator.of(context).pop();

      if (result != null && result.barcodes.isNotEmpty) {
        final barcode = result.barcodes.first;
        if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
          final data = barcode.rawValue!;
          setState(() {
            _isScanned = true;
            _scannedData = data;
          });

          _cameraController?.stop();

          if (_isValidUrl(data)) {
            _openExamWithSecurity(data);
          } else {
            _showSuccessDialog(data);
          }
          return;
        }
      }
      
      _showNoQRCodeFoundDialog();
      
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showNoQRCodeFoundDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner, size: 64, color: Colors.orange),
              SizedBox(height: 16),
              Text(
                'QR Code Tidak Ditemukan',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Pastikan gambar mengandung QR Code yang jelas dan tidak buram',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Tutup'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _pickImageFromGallery();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                      ),
                      child: Text('Coba Lagi'),
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

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned || _cameraController == null) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        final data = barcode.rawValue!;
        
        HapticFeedback.mediumImpact();
        
        setState(() {
          _isScanned = true;
          _scannedData = data;
        });

        _cameraController!.stop();

        if (_isValidUrl(data)) {
          _openExamWithSecurity(data);
        } else {
          _showSuccessDialog(data);
        }
        break;
      }
    }
  }

  bool _isValidUrl(String text) {
    if (text.startsWith('http://') || text.startsWith('https://')) return true;
    final urlPattern = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$',
    );
    return urlPattern.hasMatch(text);
  }

  Future<void> _openExamWithSecurity(String url) async {
    if (url.isEmpty) return;

    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    try {
      final uri = Uri.parse(finalUrl);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => QRWebViewScreen(url: finalUrl),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL tidak valid: $e')),
        );
      }
    }
  }

  void _showSuccessDialog(String data) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle, size: 48, color: Colors.green),
              ),
              SizedBox(height: 16),
              Text(
                'QR Code Terdeteksi',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  data,
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Data bukan URL yang valid',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      child: Text('Batal'),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop(data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                      ),
                      child: Text('Lanjutkan'),
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

  void _toggleFlash() {
    if (_cameraController == null) return;
    _cameraController!.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
  }

  void _switchCamera() {
    if (_cameraController == null) return;
    _cameraController!.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      if (_permissionDenied) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    SizedBox(height: 32),
                    Text(
                      'Izin Kamera Ditolak',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Aplikasi memerlukan akses kamera untuk memindai QR Code ujian',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async => await openAppSettings(),
                        icon: Icon(Icons.settings),
                        label: Text('Buka Pengaturan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickImageFromGallery,
                        icon: Icon(Icons.photo_library),
                        label: Text('Pilih dari Galeri'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
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
      } else {
        return Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primaryGreen),
                ),
                SizedBox(height: 16),
                Text(
                  'Meminta izin kamera...',
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          'Scan QR Code Ujian',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Camera View
          MobileScanner(
            controller: _cameraController!,
            onDetect: _onDetect,
          ),
          
          // Overlay dengan scan area
          CustomPaint(
            painter: ModernScannerOverlay(context: context),
            child: Container(),
          ),
          
          // Animasi scan line
          AnimatedBuilder(
            animation: _scanLineAnimation,
            builder: (context, child) {
              final scanSize = MediaQuery.of(context).size.width * 0.7;
              final top = (MediaQuery.of(context).size.height - scanSize) / 2;
              
              return Positioned(
                left: (MediaQuery.of(context).size.width - scanSize) / 2,
                top: top + (scanSize * _scanLineAnimation.value),
                child: Container(
                  width: scanSize,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
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
              );
            },
          ),
          
          // Instruksi
          Positioned(
            bottom: 180,
            left: 32,
            right: 32,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: AppColors.primaryGreen, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Arahkan kamera ke QR Code',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Control buttons (bottom)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModernButton(
                  icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                  label: 'Flash',
                  onTap: _toggleFlash,
                  isActive: _isFlashOn,
                ),
                _buildModernButton(
                  icon: Icons.photo_library,
                  label: 'Galeri',
                  onTap: _pickImageFromGallery,
                ),
                _buildModernButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Balik',
                  onTap: _switchCamera,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive 
              ? AppColors.primaryGreen.withOpacity(0.2)
              : Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primaryGreen : Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primaryGreen : Colors.white,
              size: 24,
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: isActive ? AppColors.primaryGreen : Colors.white,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModernScannerOverlay extends CustomPainter {
  final BuildContext context;

  ModernScannerOverlay({required this.context});

  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.width * 0.7;
    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanSize,
      height: scanSize,
    );

    // Dark overlay
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanArea, Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withOpacity(0.6),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanArea, Radius.circular(24)),
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Corner indicators
    final cornerLength = scanSize * 0.12;
    final cornerPaint = Paint()
      ..color = AppColors.primaryGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(
      scanArea.topLeft + Offset(24, 0),
      scanArea.topLeft + Offset(24 + cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.topLeft + Offset(0, 24),
      scanArea.topLeft + Offset(0, 24 + cornerLength),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      scanArea.topRight + Offset(-24, 0),
      scanArea.topRight + Offset(-24 - cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.topRight + Offset(0, 24),
      scanArea.topRight + Offset(0, 24 + cornerLength),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      scanArea.bottomLeft + Offset(24, 0),
      scanArea.bottomLeft + Offset(24 + cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.bottomLeft + Offset(0, -24),
      scanArea.bottomLeft + Offset(0, -24 - cornerLength),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      scanArea.bottomRight + Offset(-24, 0),
      scanArea.bottomRight + Offset(-24 - cornerLength, 0),
      cornerPaint,
    );
    canvas.drawLine(
      scanArea.bottomRight + Offset(0, -24),
      scanArea.bottomRight + Offset(0, -24 - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}