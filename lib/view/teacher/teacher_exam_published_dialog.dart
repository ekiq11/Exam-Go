import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../constant/app_colors.dart';
import '../teacher_monitoring_screen.dart';

class TeacherExamPublishedDialog extends StatefulWidget {
  final String examTitle;
  final String token;
  final String qrPayload;

  const TeacherExamPublishedDialog({
    super.key,
    required this.examTitle,
    required this.token,
    required this.qrPayload,
  });

  static Future<void> show(
    BuildContext context, {
    required String examTitle,
    required String token,
    required String qrPayload,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TeacherExamPublishedDialog(
        examTitle: examTitle,
        token: token,
        qrPayload: qrPayload,
      ),
    );
  }

  @override
  State<TeacherExamPublishedDialog> createState() => _TeacherExamPublishedDialogState();
}

class _TeacherExamPublishedDialogState extends State<TeacherExamPublishedDialog> {
  final GlobalKey _qrRepaintKey = GlobalKey();
  bool _isSharing = false;

  Future<void> _shareQrCode() async {
    setState(() => _isSharing = true);
    try {
      final boundary = _qrRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/QR_Ujian_${widget.token}.png').create();
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'QR Code & Token Ujian: ${widget.examTitle}',
          text: 'QR Code & Token Ujian: ${widget.examTitle}\nToken: ${widget.token}',
        ),
      );
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _copyToken() {
    Clipboard.setData(ClipboardData(text: widget.token));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Token ${widget.token} disalin ke clipboard!'),
        backgroundColor: AppColors.primaryGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Success
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Ujian Berhasil Diterbitkan!',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1B5E20)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.examTitle,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Token Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Column(
                children: [
                  Text(
                    'TOKEN UJIAN SISWA',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryGreen, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.token,
                        style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800, color: const Color(0xFF1B5E20), letterSpacing: 4),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppColors.primaryGreen, size: 22),
                        tooltip: 'Salin Token',
                        onPressed: _copyToken,
                      ),
                    ],
                  ),
                  Text(
                    'Siswa dapat mengetik token ini langsung di beranda',
                    style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // QR Code Box (Capture-able)
            RepaintBoundary(
              key: _qrRepaintKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: widget.qrPayload,
                      version: QrVersions.auto,
                      size: 190.0,
                      gapless: true,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF1B5E20),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ExamGO Official QR Code',
                      style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSharing ? null : _shareQrCode,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text('Bagikan QR', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Tutup dialog
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TeacherMonitoringListScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.monitor_heart_rounded, color: Colors.white, size: 18),
                    label: Text('Monitoring', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: Text('Kembali ke Menu Utama', style: GoogleFonts.poppins(color: Colors.grey[700], fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

