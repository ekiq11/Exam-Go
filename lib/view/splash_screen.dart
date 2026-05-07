// lib/view/splash_screen.dart
// ignore_for_file: deprecated_member_use
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/constant/update.dart';
import 'package:examgo/view/onboardong_screen.dart';
import 'package:examgo/view/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  late final AnimationController _breatheCtrl;
  late final Animation<double> _breathe;

  late final AnimationController _loadCtrl;

  String _statusText = 'Memulai...';

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _slide = Tween<double>(
      begin: 20,
      end: 0,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _breathe = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _breatheCtrl, curve: Curves.easeInOut));

    _loadCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _entryCtrl.forward();
    _initSequence();
  }

  Future<void> _initSequence() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    _setStatus('Memeriksa pembaruan...');
    final updateInfo = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;

    if (updateInfo != null && updateInfo.hasUpdate) {
      _setStatus('Update tersedia ✨');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await showUpdateDialog(context, updateInfo);
      if (!mounted) return;
    }

    _setStatus('Masuk...');
    final done = await isOnboardingDone();
    if (!mounted) return;

    if (done) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/onboarding');
    }
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _breatheCtrl.dispose();
    _loadCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = context.isTablet ? 110.0 : context.rs(96);
    final iconSize = context.isTablet ? 50.0 : context.rs(44);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1B5E20),
              AppColors.primaryGreen,
              Color(0xFF388E3C),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Lingkaran dekoratif atas-kanan
            Positioned(
              top: -size.height * 0.18,
              right: -size.width * 0.22,
              child: Container(
                width: size.width * 0.9,
                height: size.width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1B5E20).withOpacity(0.35),
                ),
              ),
            ),
            // Lingkaran dekoratif bawah-kiri
            Positioned(
              bottom: -size.height * 0.12,
              left: -size.width * 0.18,
              child: Container(
                width: size.width * 0.75,
                height: size.width * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2E7D32).withOpacity(0.25),
                ),
              ),
            ),

            // Konten utama
            SafeArea(
              child: AnimatedBuilder(
                animation: _entryCtrl,
                builder: (_, child) => Opacity(
                  opacity: _fade.value,
                  child: Transform.translate(
                    offset: Offset(0, _slide.value),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.rs(32)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 4),

                      // ── Logo ──
                      AnimatedBuilder(
                        animation: _breathe,
                        builder: (_, child) => Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.12),
                            border: Border.all(
                              color: Colors.white.withOpacity(
                                0.28 + _breathe.value * 0.18,
                              ),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(
                                  0.08 + _breathe.value * 0.08,
                                ),
                                blurRadius: 30,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.school_rounded,
                            size: iconSize,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      SizedBox(height: context.rs(24)),

                      // ── App name ──
                      Text(
                        AppConfig.appName,
                        style: GoogleFonts.poppins(
                          fontSize: context.isTablet ? 34.0 : context.rs(32),
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 2,
                          height: 1.1,
                        ),
                      ),

                      SizedBox(height: context.rs(6)),

                      // ── Tagline ──
                      Text(
                        'Secure Exam Browser',
                        style: GoogleFonts.poppins(
                          fontSize: context.isTablet ? 13.0 : context.rs(12),
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.75),
                          letterSpacing: 0.3,
                          height: 1.4,
                        ),
                      ),

                      SizedBox(height: context.rs(16)),

                      // ── Chip versi ──
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rs(12),
                          vertical: context.rs(4),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'v${AppConfig.appVersion}',
                          style: GoogleFonts.poppins(
                            fontSize: context.rs(10),
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.70),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),

                      const Spacer(flex: 4),

                      // ── Loader + status ──
                      Padding(
                        padding: EdgeInsets.only(bottom: context.rs(48)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _GrainWaveLoader(
                              ctrl: _loadCtrl,
                              grainSize: context.rs(8),
                              spacing: context.rs(5),
                            ),
                            SizedBox(height: context.rs(14)),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: Text(
                                _statusText,
                                key: ValueKey(_statusText),
                                style: GoogleFonts.poppins(
                                  fontSize: context.rs(11),
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withOpacity(0.60),
                                  letterSpacing: 0.2,
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
          ],
        ),
      ),
    );
  }
}

/// Wave ripple loader — 5 butir bergelombang kiri ke kanan
class _GrainWaveLoader extends StatelessWidget {
  const _GrainWaveLoader({
    required this.ctrl,
    required this.grainSize,
    required this.spacing,
  });

  final AnimationController ctrl;
  final double grainSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    const count = 5;
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(count, (i) {
            final phase = (ctrl.value - i * (1.0 / count)) % 1.0;
            final normalized = phase < 0 ? phase + 1.0 : phase;

            double scale;
            if (normalized < 0.4) {
              scale = 0.4 + (normalized / 0.4) * 0.6;
            } else if (normalized < 0.8) {
              scale = 1.0 - ((normalized - 0.4) / 0.4) * 0.6;
            } else {
              scale = 0.4;
            }

            final opacity = 0.35 + scale * 0.65;

            return Container(
              margin: EdgeInsets.symmetric(horizontal: spacing * 0.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: grainSize,
                  height: grainSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(opacity),
                    boxShadow: scale > 0.7
                        ? [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.22),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
