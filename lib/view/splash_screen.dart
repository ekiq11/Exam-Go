// ignore_for_file: deprecated_member_use
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/app_config.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:examgo/view/onboardong_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    // Status bar transparan saat splash
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _scale = Tween<double>(
      begin: 0.6,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();

    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final done = await isOnboardingDone();
      if (!mounted) return;
      if (done) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Skala ikon berdasarkan device
    final iconSize = context.isTablet ? 130.0 : context.rs(110);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryGreen,
              AppColors.primaryGreen.withOpacity(0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.school,
                        size: iconSize * 0.5,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    SizedBox(height: context.rs(28)),
                    Text(
                      AppConfig.appName,
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(30),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: context.rs(6)),
                    Text(
                      'Secure Exam Browser',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(14),
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    SizedBox(height: context.rs(6)),
                    Text(
                      'v${AppConfig.appVersion}',
                      style: GoogleFonts.poppins(
                        fontSize: context.rs(11),
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    SizedBox(height: context.rs(48)),
                    SizedBox(
                      width: context.rs(28),
                      height: context.rs(28),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
