// ignore_for_file: deprecated_member_use
import 'dart:math' as math;
import 'package:examgo/constant/app_colors.dart';
import 'package:examgo/constant/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingDone = 'onboarding_done_v1';

Future<bool> isOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingDone) ?? false;
}

Future<void> markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingDone, true);
}

class _OnboardPage {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final bool isDark;
  final List<String> bulletPoints;

  const _OnboardPage({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.isDark,
    required this.bulletPoints,
  });
}

const _pages = [
  _OnboardPage(
    isDark: true,
    icon: Icons.school_rounded,
    title: 'Selamat Datang di',
    subtitle: 'ExamGO',
    description:
        'Aplikasi ujian digital yang aman, terenkripsi, dan dirancang khusus untuk lingkungan pendidikan Indonesia.',
    bulletPoints: [
      'Ujian online tanpa risiko kecurangan',
      'QR Code terenkripsi HMAC-SHA256',
      'Dikembangkan untuk sekolah & madrasah',
    ],
  ),
  _OnboardPage(
    isDark: false,
    icon: Icons.qr_code_scanner_rounded,
    title: 'Scan QR,',
    subtitle: 'Mulai Ujian',
    description:
        'Pengawas cukup menampilkan QR Code di layar. Peserta scan menggunakan ExamGO — ujian langsung dimulai dalam hitungan detik.',
    bulletPoints: [
      'Scan via kamera atau galeri foto',
      'QR hanya bisa dibaca ExamGO',
      'Tidak perlu input URL manual',
    ],
  ),
  _OnboardPage(
    isDark: true,
    icon: Icons.lock_rounded,
    title: 'Mode Ujian',
    subtitle: 'Terkunci Penuh',
    description:
        'Saat ujian berlangsung, aplikasi mengaktifkan mode keamanan penuh untuk memastikan kejujuran setiap peserta.',
    bulletPoints: [
      'Layar penuh — tidak bisa minimize',
      'Orientasi terkunci portrait',
      'Klik kanan & seleksi diblokir',
    ],
  ),
  _OnboardPage(
    isDark: false,
    icon: Icons.verified_user_rounded,
    title: 'Tanggung Jawab',
    subtitle: 'yang Jelas',
    description:
        'ExamGO adalah jembatan antara perangkat dan server ujian. Proses ujian dikelola sepenuhnya oleh server penyelenggara.',
    bulletPoints: [
      'ExamGO = penghubung ke server ujian',
      'Gangguan server bukan tanggung jawab ExamGO',
      'Pastikan koneksi internet stabil',
    ],
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  late final List<AnimationController> _fadeControllers;
  late final List<AnimationController> _slideControllers;

  @override
  void initState() {
    super.initState();
    _fadeControllers = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _slideControllers = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      ),
    );
    _animatePage(0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _fadeControllers) c.dispose();
    for (final c in _slideControllers) c.dispose();
    super.dispose();
  }

  void _animatePage(int index) {
    _fadeControllers[index].forward(from: 0);
    _slideControllers[index].forward(from: 0);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _animatePage(index);
    HapticFeedback.selectionClick();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    await markOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _pages[_currentPage].isDark;

    // Status bar menyesuaikan warna halaman, berlaku di iOS & Android
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        // iOS-specific
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: _pages.length,
            itemBuilder: (_, i) => _buildPage(i),
          ),

          // Skip button
          if (_currentPage < _pages.length - 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + context.rs(16),
              right: context.rs(20),
              child: GestureDetector(
                onTap: _skip,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.rs(16),
                    vertical: context.rs(8),
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.3)
                          : Colors.black.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Lewati',
                    style: GoogleFonts.poppins(
                      fontSize: context.rs(12),
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    final page = _pages[index];
    final fadeAnim = CurvedAnimation(
      parent: _fadeControllers[index],
      curve: Curves.easeOut,
    );
    final slideAnim = CurvedAnimation(
      parent: _slideControllers[index],
      curve: Curves.easeOutCubic,
    );
    return page.isDark
        ? _buildDarkPage(page, index, fadeAnim, slideAnim)
        : _buildLightPage(page, index, fadeAnim, slideAnim);
  }

  // ── DARK page ─────────────────────────────────────────────────
  Widget _buildDarkPage(
    _OnboardPage page,
    int index,
    Animation<double> fade,
    Animation<double> slide,
  ) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          ..._buildDarkDecorations(),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              // SingleChildScrollView mencegah overflow di layar mungil
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: context.rs(60)),
                    _animatedIcon(
                      page.icon,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(36)),
                    _animatedTitle(
                      page,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(20)),
                    FadeTransition(
                      opacity: fade,
                      child: Text(
                        page.description,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: context.rs(13),
                          height: 1.7,
                        ),
                      ),
                    ),
                    SizedBox(height: context.rs(28)),
                    ..._buildBullets(
                      page.bulletPoints,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(140)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LIGHT page ────────────────────────────────────────────────
  Widget _buildLightPage(
    _OnboardPage page,
    int index,
    Animation<double> fade,
    Animation<double> slide,
  ) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          ..._buildLightDecorations(),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: context.rs(60)),
                    _animatedIcon(
                      page.icon,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(36)),
                    _animatedTitle(
                      page,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(20)),
                    FadeTransition(
                      opacity: fade,
                      child: Text(
                        page.description,
                        style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: context.rs(13),
                          height: 1.7,
                        ),
                      ),
                    ),
                    SizedBox(height: context.rs(28)),
                    ..._buildBullets(
                      page.bulletPoints,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(140)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared animated widgets ────────────────────────────────────

  Widget _animatedIcon(
    IconData icon, {
    required bool isDark,
    required Animation<double> fade,
    required Animation<double> slide,
  }) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(slide),
        child: _buildIconBox(icon, isDark: isDark),
      ),
    );
  }

  Widget _animatedTitle(
    _OnboardPage page, {
    required bool isDark,
    required Animation<double> fade,
    required Animation<double> slide,
  }) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(slide),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page.title,
              style: GoogleFonts.poppins(
                color: isDark
                    ? Colors.white.withOpacity(0.75)
                    : AppColors.textSecondary,
                fontSize: context.rs(18),
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
            Text(
              page.subtitle,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : AppColors.primaryGreen,
                fontSize: context.rs(36),
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBullets(
    List<String> bullets, {
    required bool isDark,
    required Animation<double> fade,
    required Animation<double> slide,
  }) {
    return bullets.asMap().entries.map((e) {
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, 0.1 * (e.key + 1)),
            end: Offset.zero,
          ).animate(slide),
          child: Padding(
            padding: EdgeInsets.only(bottom: context.rs(12)),
            child: Row(
              children: [
                Container(
                  width: context.rs(28),
                  height: context.rs(28),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.15)
                        : AppColors.paleGreen,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.3)
                          : AppColors.primaryGreen.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.check_rounded,
                      color: isDark ? Colors.white : AppColors.primaryGreen,
                      size: context.rs(14),
                    ),
                  ),
                ),
                SizedBox(width: context.rs(12)),
                Expanded(
                  child: Text(
                    e.value,
                    style: GoogleFonts.poppins(
                      color: isDark
                          ? Colors.white.withOpacity(0.88)
                          : AppColors.textPrimary,
                      fontSize: context.rs(13),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildIconBox(IconData icon, {required bool isDark}) {
    return Container(
      width: context.rs(80),
      height: context.rs(80),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.15)
            : AppColors.primaryGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.25)
              : AppColors.primaryGreen.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.15)
                : AppColors.primaryGreen.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: context.rs(38),
          color: isDark ? Colors.white : AppColors.primaryGreen,
        ),
      ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final page = _pages[_currentPage];
    final isDark = page.isDark;
    final isLast = _currentPage == _pages.length - 1;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xFF1B5E20)],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white.withOpacity(0.98)],
              ),
      ),
      padding: EdgeInsets.fromLTRB(
        context.horizontalPadding,
        context.rs(32),
        context.horizontalPadding,
        MediaQuery.of(context).padding.bottom + context.rs(28),
      ),
      child: Row(
        children: [
          // Dot indicators
          Row(
            children: List.generate(_pages.length, (i) {
              final isActive = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: EdgeInsets.only(right: context.rs(6)),
                width: isActive ? context.rs(24) : context.rs(8),
                height: context.rs(8),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? Colors.white : AppColors.primaryGreen)
                      : (isDark
                            ? Colors.white.withOpacity(0.3)
                            : AppColors.primaryGreen.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const Spacer(),

          // Next / Mulai button
          GestureDetector(
            onTap: _nextPage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(
                horizontal: isLast ? context.rs(28) : context.rs(20),
                vertical: context.rs(14),
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.white : AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.2)
                        : AppColors.primaryGreen.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLast) ...[
                    Icon(
                      Icons.rocket_launch_rounded,
                      color: isDark ? AppColors.primaryGreen : Colors.white,
                      size: context.rs(18),
                    ),
                    SizedBox(width: context.rs(8)),
                  ],
                  Text(
                    isLast ? 'Mulai Sekarang' : 'Selanjutnya',
                    style: GoogleFonts.poppins(
                      color: isDark ? AppColors.primaryGreen : Colors.white,
                      fontSize: context.rs(14),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!isLast) ...[
                    SizedBox(width: context.rs(8)),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: isDark ? AppColors.primaryGreen : Colors.white,
                      size: context.rs(16),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Background decorations ─────────────────────────────────────
  List<Widget> _buildDarkDecorations() => [
    Positioned(
      top: -80,
      right: -60,
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.05),
        ),
      ),
    ),
    Positioned(
      bottom: 80,
      left: -40,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.04),
        ),
      ),
    ),
    Positioned(
      right: 20,
      bottom: 160,
      child: Opacity(
        opacity: 0.15,
        child: SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(painter: _DotGridPainter(color: Colors.white)),
        ),
      ),
    ),
    Positioned.fill(
      child: CustomPaint(
        painter: _DiagonalLinePainter(color: Colors.white.withOpacity(0.04)),
      ),
    ),
  ];

  List<Widget> _buildLightDecorations() => [
    Positioned(
      top: -100,
      right: -80,
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryGreen.withOpacity(0.06),
        ),
      ),
    ),
    Positioned(
      bottom: 60,
      left: -50,
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryGreen.withOpacity(0.05),
        ),
      ),
    ),
    Positioned(
      right: 20,
      bottom: 160,
      child: Opacity(
        opacity: 0.12,
        child: SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(
            painter: _DotGridPainter(color: AppColors.primaryGreen),
          ),
        ),
      ),
    ),
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 4,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryGreen, Color(0xFF81C784)],
          ),
        ),
      ),
    ),
  ];
}

// ─── Painters ─────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 14.0;
    const radius = 1.8;
    final paint = Paint()..color = color;
    for (double x = 0; x <= size.width; x += spacing) {
      for (double y = 0; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DiagonalLinePainter extends CustomPainter {
  final Color color;
  const _DiagonalLinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const spacing = 60.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
