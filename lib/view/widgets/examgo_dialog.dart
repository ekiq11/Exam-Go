import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../constant/app_colors.dart';

/// Komponen dialog terpadu dengan desain modern, proporsional, dan elegan khas ExamGO.
/// Anti-overflow pada semua ukuran layar, mendukung mode konfirmasi, informasi, input, dan bahaya.
class ExamGoDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String message;
  final Widget? content;
  final String confirmText;
  final VoidCallback? onConfirm;
  final String? cancelText;
  final VoidCallback? onCancel;
  final bool isDestructive;
  final bool showCancel;

  const ExamGoDialog({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.message,
    this.content,
    this.confirmText = 'Lanjutkan',
    this.onConfirm,
    this.cancelText = 'Batal',
    this.onCancel,
    this.isDestructive = false,
    this.showCancel = true,
  });

  /// Dialog Konfirmasi Standar
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Ya, Lanjutkan',
    String cancelText = 'Batal',
    IconData icon = Icons.help_outline_rounded,
    Color iconColor = const Color(0xFF0D9488),
    Color iconBgColor = const Color(0xFFE6FFFA),
    bool isDestructive = false,
  }) {
    HapticFeedback.lightImpact();
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ExamGoDialog(
        icon: icon,
        iconColor: isDestructive ? const Color(0xFFDC2626) : iconColor,
        iconBgColor: isDestructive ? const Color(0xFFFEE2E2) : iconBgColor,
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: isDestructive,
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  /// Dialog Informasi / Peringatan
  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'Mengerti',
    IconData icon = Icons.info_outline_rounded,
    Color iconColor = const Color(0xFF2563EB),
    Color iconBgColor = const Color(0xFFEFF6FF),
  }) {
    HapticFeedback.lightImpact();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ExamGoDialog(
        icon: icon,
        iconColor: iconColor,
        iconBgColor: iconBgColor,
        title: title,
        message: message,
        confirmText: buttonText,
        showCancel: false,
        onConfirm: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  /// Dialog Bahaya / Tindakan Destruktif (Hapus Akun / Hapus Data)
  static Future<bool?> danger(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Hapus Permanen',
    String cancelText = 'Batal',
    IconData icon = Icons.warning_amber_rounded,
  }) {
    HapticFeedback.heavyImpact();
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => ExamGoDialog(
        icon: icon,
        iconColor: const Color(0xFFDC2626),
        iconBgColor: const Color(0xFFFEE2E2),
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: true,
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Icon Pill
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isDark ? iconColor.withValues(alpha: 0.2) : iconBgColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            color: iconColor,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Title
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Message
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          height: 1.45,
                        ),
                      ),

                      // Custom Additional Content (e.g. TextField, list, etc.)
                      if (content != null) ...[
                        const SizedBox(height: 14),
                        content!,
                      ],

                      const SizedBox(height: 20),

                      // Action Buttons
                      Row(
                        children: [
                          if (showCancel) ...[
                            Expanded(
                              child: TextButton(
                                onPressed: onCancel ?? () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  backgroundColor: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : const Color(0xFFF1F5F9),
                                ),
                                child: Text(
                                  cancelText ?? 'Batal',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: onConfirm,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                backgroundColor: isDestructive
                                    ? const Color(0xFFDC2626)
                                    : AppColors.primaryGreen,
                              ),
                              child: Text(
                                confirmText,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
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
            ),
          ),
        ),
      ),
    );
  }
}
