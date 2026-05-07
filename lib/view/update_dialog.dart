// lib/view/update_dialog.dart
// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/constant/update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tampilkan dialog update. Return true jika user menekan Update.
Future<bool> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    // barrierDismissible false untuk major update — tapi back gesture
    // tetap diblokir via PopScope di dalam widget
    barrierDismissible: !info.isMajorUpdate,
    barrierLabel: '',
    barrierColor: Colors.black.withOpacity(0.75),
    transitionDuration: const Duration(milliseconds: 500),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutExpo);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
    pageBuilder: (ctx, _, child) => _UpdateDialog(info: info),
  );
  return result ?? false;
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _badgeCtrl;
  late final AnimationController _staggerCtrl;
  late final Animation<double> _bgAnim;
  late final Animation<double> _badgePulse;

  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _badgeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);
    _badgePulse = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _badgeCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _particleCtrl.dispose();
    _badgeCtrl.dispose();
    _staggerCtrl.dispose();
    super.dispose();
  }

  Future<void> _onUpdate() async {
    if (_isLaunching) return;
    setState(() => _isLaunching = true);
    HapticFeedback.heavyImpact();

    try {
      final uri = Uri.parse(widget.info.downloadUrl);
      final launched = await canLaunchUrl(uri);
      if (launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        // Tutup dialog setelah berhasil buka link
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      // Fallback: URL tidak bisa dibuka — beri tahu user
      if (mounted) {
        setState(() => _isLaunching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tidak bisa membuka link. Coba buka browser secara manual.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  Future<void> _onSkip() async {
    HapticFeedback.lightImpact();
    await UpdateService.instance.skipVersion(widget.info.latestVersion);
    if (mounted) Navigator.of(context).pop(false);
  }

  void _onLater() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: PopScope blokir back gesture/button pada major update
    return PopScope(
      canPop: !widget.info.isMajorUpdate,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Material(color: Colors.transparent, child: _buildSheet()),
        ),
      ),
    );
  }

  Widget _buildSheet() {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: context.isTablet ? 520.0 : double.infinity,
      ),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        color: const Color(0xFF0D0D0D),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: Stack(
          children: [_buildAnimatedBg(), _buildParticles(), _buildContent()],
        ),
      ),
    );
  }

  Widget _buildAnimatedBg() {
    return AnimatedBuilder(
      animation: _bgAnim,
      builder: (_, child) {
        final t = _bgAnim.value;
        return Container(
          height: 320,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6 + t * 1.2, -0.8 + t * 0.4),
              radius: 1.2,
              colors: [
                const Color(0xFF1A4731).withOpacity(0.9),
                const Color(0xFF0F2A1C).withOpacity(0.6),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticles() {
    return SizedBox(
      height: 280,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _particleCtrl,
        builder: (_, child) =>
            CustomPaint(painter: _ParticlePainter(_particleCtrl.value)),
      ),
    );
  }

  Widget _buildContent() {
    // FIXED: hapus local variable `info` yang duplikat dengan getter
    // Pakai widget.info secara konsisten di seluruh build method
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.rs(24),
        context.rs(12),
        context.rs(24),
        context.rs(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: context.rs(28)),
          _staggerItem(0.0, _buildVersionBadge()),
          SizedBox(height: context.rs(20)),
          _staggerItem(
            0.1,
            Text(
              'Update Tersedia! 🚀',
              style: GoogleFonts.spaceGrotesk(
                fontSize: context.rs(26),
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: context.rs(8)),
          _staggerItem(
            0.15,
            Text(
              'Versi terbaru udah nunggu kamu nih',
              style: GoogleFonts.poppins(
                fontSize: context.rs(13),
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: context.rs(24)),
          _staggerItem(0.2, _buildVersionCard()),
          SizedBox(height: context.rs(16)),

          // FIXED: cek releaseNotes setelah filter, bukan sebelum
          Builder(
            builder: (_) {
              final lines = widget.info.releaseNotes
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .take(4)
                  .toList();
              if (lines.isNotEmpty) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _staggerItem(0.25, _buildReleaseNotes(lines)),
                    SizedBox(height: context.rs(24)),
                  ],
                );
              }
              return SizedBox(height: context.rs(8));
            },
          ),

          _staggerItem(0.35, _buildButtons()),

          if (!widget.info.isMajorUpdate) ...[
            SizedBox(height: context.rs(16)),
            _staggerItem(0.4, _buildSkipLink()),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionBadge() {
    return ScaleTransition(
      scale: _badgePulse,
      child: Container(
        width: context.rs(72),
        height: context.rs(72),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ECC71).withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '↑',
            style: GoogleFonts.spaceGrotesk(
              fontSize: context.rs(32),
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.rs(20),
        vertical: context.rs(16),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _versionChip(
            widget.info.currentVersion,
            const Color(0xFF444444),
            const Color(0xFF888888),
            'Sekarang',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.rs(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2ECC71).withOpacity(0.3 + i * 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _versionChip(
            widget.info.latestVersion,
            const Color(0xFF1A3D28),
            const Color(0xFF2ECC71),
            'Terbaru',
          ),
        ],
      ),
    );
  }

  Widget _versionChip(String version, Color bg, Color fg, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.rs(14),
            vertical: context.rs(8),
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: fg.withOpacity(0.3), width: 1),
          ),
          child: Text(
            'v$version',
            style: GoogleFonts.spaceGrotesk(
              fontSize: context.rs(15),
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(height: context.rs(6)),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: context.rs(10),
            color: Colors.white.withOpacity(0.35),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // FIXED: terima `lines` yang sudah difilter dari _buildContent
  Widget _buildReleaseNotes(List<String> lines) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.rs(16)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: context.rs(8)),
              Text(
                "What's New",
                style: GoogleFonts.spaceGrotesk(
                  fontSize: context.rs(12),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2ECC71),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: context.rs(12)),
          ...lines.map(
            (line) => Padding(
              padding: EdgeInsets.only(bottom: context.rs(7)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: context.rs(5)),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2ECC71),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  SizedBox(width: context.rs(10)),
                  Expanded(
                    child: Text(
                      line.replaceAll(RegExp(r'^[-•*]\s*'), ''),
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(12),
                        color: Colors.white.withOpacity(0.65),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        GestureDetector(
          onTap: _isLaunching ? null : _onUpdate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: context.rs(17)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2ECC71), Color(0xFF25A25A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: _isLaunching
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFF2ECC71).withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Center(
              child: _isLaunching
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.rocket_launch_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: context.rs(10)),
                        Text(
                          'Update Sekarang',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: context.rs(15),
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (!widget.info.isMajorUpdate) ...[
          SizedBox(height: context.rs(10)),
          GestureDetector(
            onTap: _onLater,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: context.rs(15)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  'Nanti Aja Deh',
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(14),
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSkipLink() {
    return GestureDetector(
      onTap: _onSkip,
      child: Text(
        'Lewatin versi ${widget.info.latestVersion}',
        style: GoogleFonts.poppins(
          fontSize: context.rs(11),
          color: Colors.white.withOpacity(0.25),
          decoration: TextDecoration.underline,
          decorationColor: Colors.white.withOpacity(0.15),
        ),
      ),
    );
  }

  Widget _staggerItem(double delayFraction, Widget child) {
    final start = delayFraction.clamp(0.0, 0.9);
    final end = (start + 0.4).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

// ── Particle painter ─────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final double progress;
  _ParticlePainter(this.progress);

  static final _rng = math.Random(42);
  static final _particles = List.generate(
    18,
    (_) => [
      _rng.nextDouble(), // x fraction
      _rng.nextDouble(), // y fraction
      _rng.nextDouble() * 0.6 + 0.2, // speed
      _rng.nextDouble() * 3 + 1.5, // radius
      _rng.nextDouble(), // phase
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress * p[2] + p[4]) % 1.0;
      final x = p[0] * size.width;
      final y = size.height - t * size.height * 1.3;
      final opacity = (math.sin(t * math.pi)).clamp(0.0, 1.0) * 0.35;
      if (opacity < 0.01) continue;
      canvas.drawCircle(
        Offset(x, y),
        p[3],
        Paint()
          ..color = const Color(0xFF2ECC71).withOpacity(opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
