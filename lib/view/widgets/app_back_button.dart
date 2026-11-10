import 'package:flutter/material.dart';

/// Tombol Back standar ExamGO yang konsisten, modern, elegan, dan profesional.
///
/// Menyediakan 2 varian tema visual:
/// - [AppBackButton.light]: Khusus AppBar gelap / gradient (hijau, teal, hitam) dengan efek frosted glass putih.
/// - [AppBackButton.dark]: Khusus AppBar terang / putih dengan latar slate halus dan border tipis.
/// - [AppBackButton.close]: Tombol Tutup (X) dengan estetika dan dimensi lingkaran yang sama.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLight;
  final String tooltip;
  final IconData icon;
  final EdgeInsetsGeometry? padding;

  const AppBackButton({
    super.key,
    this.onPressed,
    this.isLight = true,
    this.tooltip = 'Kembali',
    this.icon = Icons.arrow_back_rounded,
    this.padding,
  });

  /// Varian untuk AppBar Gelap / Gradient (Teks/Ikon Putih)
  const AppBackButton.light({
    super.key,
    this.onPressed,
    this.tooltip = 'Kembali',
    this.icon = Icons.arrow_back_rounded,
    this.padding,
  }) : isLight = true;

  /// Varian untuk AppBar Terang / Putih (Teks/Ikon Gelap)
  const AppBackButton.dark({
    super.key,
    this.onPressed,
    this.tooltip = 'Kembali',
    this.icon = Icons.arrow_back_rounded,
    this.padding,
  }) : isLight = false;

  /// Varian Tombol Tutup / Close (X) dengan estetika circular frosted yang sama
  const AppBackButton.close({
    super.key,
    this.onPressed,
    this.isLight = true,
    this.tooltip = 'Tutup',
    this.padding,
  }) : icon = Icons.close_rounded;

  @override
  Widget build(BuildContext context) {
    final bgColor = isLight
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFF1F5F9);
    final borderColor = isLight
        ? Colors.white.withValues(alpha: 0.25)
        : const Color(0xFFE2E8F0);
    final iconColor = isLight ? Colors.white : const Color(0xFF0F172A);

    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 12, top: 8, bottom: 8),
      child: Center(
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed ?? () => Navigator.maybePop(context),
            child: Tooltip(
              message: tooltip,
              child: Ink(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 19,
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
