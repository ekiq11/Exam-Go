import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constant/app_colors.dart';

/// Controller untuk memperbarui status teks atau menutup dialog loading dari luar secara dinamis.
class ExamGoLoadingController {
  final ValueNotifier<String> messageNotifier;
  final ValueNotifier<String> titleNotifier;
  BuildContext? _dialogContext;
  bool _isDismissed = false;

  ExamGoLoadingController({
    required String initialTitle,
    required String initialMessage,
  })  : titleNotifier = ValueNotifier<String>(initialTitle),
        messageNotifier = ValueNotifier<String>(initialMessage);

  void attachContext(BuildContext dialogContext) {
    _dialogContext = dialogContext;
    if (_isDismissed) {
      if (dialogContext.mounted && Navigator.canPop(dialogContext)) {
        Navigator.of(dialogContext).pop();
      }
    }
  }

  void update({String? title, String? message}) {
    if (_isDismissed) return;
    if (title != null) titleNotifier.value = title;
    if (message != null) messageNotifier.value = message;
  }

  void dismiss() {
    if (_isDismissed) return;
    _isDismissed = true;
    final ctx = _dialogContext;
    if (ctx != null && ctx.mounted && Navigator.canPop(ctx)) {
      Navigator.of(ctx).pop();
    }
  }
}

/// Dialog loading modern, profesional, dan elegan khas ExamGO.
/// Menampilkan animasi pulse & progress dengan informasi status pencarian token yang transparan.
class ExamGoLoadingDialog extends StatelessWidget {
  final ValueNotifier<String> titleNotifier;
  final ValueNotifier<String> messageNotifier;

  const ExamGoLoadingDialog({
    super.key,
    required this.titleNotifier,
    required this.messageNotifier,
  });

  /// Menampilkan dialog loading profesional dan mengembalikan controller untuk kontrol dinamis.
  static ExamGoLoadingController show(
    BuildContext context, {
    String title = 'Mencari Token Ujian...',
    String message = 'Menghubungkan ke server CBT & memverifikasi token...',
  }) {
    final controller = ExamGoLoadingController(
      initialTitle: title,
      initialMessage: message,
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        controller.attachContext(ctx);
        return ExamGoLoadingDialog(
          titleNotifier: controller.titleNotifier,
          messageNotifier: controller.messageNotifier,
        );
      },
    );

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Badge Loader with ExamGO Branding
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFDCFCE7),
                          width: 2,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 54,
                      height: 54,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.manage_search_rounded,
                      color: AppColors.primaryGreen,
                      size: 28,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Dynamic Title
                ValueListenableBuilder<String>(
                  valueListenable: titleNotifier,
                  builder: (context, title, _) {
                    return Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F172A),
                        letterSpacing: 0.1,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // Dynamic Message / Status
                ValueListenableBuilder<String>(
                  valueListenable: messageNotifier,
                  builder: (context, msg, _) {
                    return Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Subtitle Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Verifikasi Enkripsi CBT ExamGO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF475569),
                          ),
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
    );
  }
}

