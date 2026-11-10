import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Overlay tirai keamanan anti-cheat yang secara instan menutup seluruh layar ujian
/// jika terdeteksi Split-Screen, Jendela Mengambang (Floating Window / Pop-up view),
/// atau kehilangan fokus layar. Mencegah siswa melihat soal saat membuka aplikasi lain.
class AntiCheatShieldOverlay extends StatelessWidget {
  final Widget child;
  final bool isShieldActive;
  final String title;
  final String message;
  final VoidCallback? onRecover;

  const AntiCheatShieldOverlay({
    super.key,
    required this.child,
    required this.isShieldActive,
    this.title = 'PERINGATAN KEAMANAN UJIAN',
    this.message =
        'Layar terbelah (Split-Screen) atau aplikasi lain mengambang terdeteksi!\n\n'
        'Demi menjaga integritas ujian, Anda dilarang membagi layar atau membuka aplikasi lain di atas ExamGO. '
        'Tutup aplikasi lain dan kembali ke mode satu layar penuh.',
    this.onRecover,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    // Deteksi dimensional split-screen di smartphone:
    // Pada mode portrait standar, tinggi layar berkisar 600 - 950 dp.
    // Saat di-split 50:50, tinggi menyusut drastis (< 500 dp) dan ratio tinggi/lebar < 1.35.
    final isSplitByDimension =
        !isLandscape &&
        mediaQuery.size.height < 500 &&
        mediaQuery.size.width > 280 &&
        (mediaQuery.size.height / mediaQuery.size.width) < 1.35;

    final shouldShowShield = isShieldActive || isSplitByDimension;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (shouldShowShield)
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0F172A), // Latar hitam solid anti-intip
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.security_update_warning_rounded,
                            color: Colors.redAccent,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (onRecover != null)
                          ElevatedButton.icon(
                            onPressed: onRecover,
                            icon: const Icon(
                              Icons.fullscreen_rounded,
                              size: 20,
                            ),
                            label: Text(
                              'Kembali ke Layar Penuh',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 4,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
