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
  final String badgeText;
  final IconData badgeIcon;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final bool isDark;
  final List<String> bulletPoints;

  const _OnboardPage({
    required this.badgeText,
    required this.badgeIcon,
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
    badgeIcon: Icons.verified_rounded,
    badgeText: 'SIMULASI CAT BKN & SNBT',
    icon: Icons.school_rounded,
    title: 'Raih Skor Tertinggi di',
    subtitle: 'ExamGO',
    description:
        'Platform simulasi ujian digital terlengkap berstandar nasional untuk persiapan UTBK-SNBT, SKD CPNS, dan Kedinasan dengan format penilaian IRT resmi.',
    bulletPoints: [
      'Format Resmi CAT BKN & UTBK-SNBT',
      'Timer Real-Time & Navigasi Subtest Otomatis',
      'Dukungan Rumus KaTeX & Tabel Kompleks',
    ],
  ),
  _OnboardPage(
    isDark: false,
    badgeIcon: Icons.security_rounded,
    badgeText: 'INTEGRITAS ANTI-CURANG',
    icon: Icons.lock_person_rounded,
    title: 'Keamanan Ujian',
    subtitle: 'Terkunci Aman',
    description:
        'Ujian berlangsung dalam lingkungan terproteksi penuh. Sistem mendeteksi perpindahan aplikasi, screenshot, dan split-screen secara otomatis.',
    bulletPoints: [
      'Kiosk Mode & Blokir Keluar Layar',
      'Anti-Screenshot & Layar Terkunci',
      'Auto-Save Detik per Detik & Crash Recovery',
    ],
  ),
  _OnboardPage(
    isDark: true,
    badgeIcon: Icons.insights_rounded,
    badgeText: 'ANALITIK SPIDER CHART',
    icon: Icons.radar_rounded,
    title: 'Pantau Kemampuan',
    subtitle: 'Grafik Radar',
    description:
        'Evaluasi komprehensif keunggulan dan target belajar Anda lewat visualisasi spider chart per subtest, status passing grade, dan pembahasan mendalam.',
    bulletPoints: [
      'Grafik Spider Radar per Subtest',
      'Kunci & Pembahasan Mendalam Tiap Soal',
      'Cetak Rapor & Sertifikat Hasil Ujian',
    ],
  ),
  _OnboardPage(
    isDark: false,
    badgeIcon: Icons.cloud_sync_rounded,
    badgeText: 'CLOUD SYNC & RESTORE',
    icon: Icons.cloud_done_rounded,
    title: 'Jawaban & Riwayat',
    subtitle: 'Aman di Cloud',
    description:
        'Khusus siswa Premium, seluruh riwayat tryout, skor, dan pembahasan tersimpan aman di Cloud. Tetap utuh saat aplikasi di-install ulang atau ganti perangkat.',
    bulletPoints: [
      'Backup Jawaban Otomatis ke Cloud Firestore',
      'Restore Riwayat saat Ganti HP / Reinstall',
      'Akses Tryout & Pembahasan Selamanya',
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
        duration: const Duration(milliseconds: 550),
      ),
    );
    _slideControllers = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      ),
    );
    _animatePage(0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _fadeControllers) {
      c.dispose();
    }
    for (final c in _slideControllers) {
      c.dispose();
    }
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
    HapticFeedback.lightImpact();
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _skip() {
    HapticFeedback.lightImpact();
    _finish();
  }

  Future<void> _finish() async {
    await markOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _pages[_currentPage].isDark;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B5E20) : Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: _pages.length,
            itemBuilder: (_, i) => _buildPage(i),
          ),

          // Tombol Lewati (Skip)
          if (_currentPage < _pages.length - 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + context.rs(14),
              right: context.rs(18),
              child: Semantics(
                button: true,
                label: 'Lewati Onboarding',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _skip,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rs(14),
                        vertical: context.rs(7),
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.08),
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
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomNav(),
          ),
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
          colors: [Color(0xFF144D17), Color(0xFF1B5E20), Color(0xFF2E7D32)],
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
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: context.rs(48)),
                    _animatedBadge(page, isDark: true, fade: fade, slide: slide),
                    SizedBox(height: context.rs(22)),
                    _animatedIcon(
                      page.icon,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(28)),
                    _animatedTitle(
                      page,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(16)),
                    FadeTransition(
                      opacity: fade,
                      child: Text(
                        page.description,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: context.rs(13),
                          height: 1.65,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(height: context.rs(24)),
                    ..._buildBullets(
                      page.bulletPoints,
                      isDark: true,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(130)),
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
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.horizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: context.rs(48)),
                    _animatedBadge(page, isDark: false, fade: fade, slide: slide),
                    SizedBox(height: context.rs(22)),
                    _animatedIcon(
                      page.icon,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(28)),
                    _animatedTitle(
                      page,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(16)),
                    FadeTransition(
                      opacity: fade,
                      child: Text(
                        page.description,
                        style: GoogleFonts.poppins(
                          color: AppColors.textSecondary,
                          fontSize: context.rs(13),
                          height: 1.65,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(height: context.rs(24)),
                    ..._buildBullets(
                      page.bulletPoints,
                      isDark: false,
                      fade: fade,
                      slide: slide,
                    ),
                    SizedBox(height: context.rs(130)),
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

  Widget _animatedBadge(
    _OnboardPage page, {
    required bool isDark,
    required Animation<double> fade,
    required Animation<double> slide,
  }) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(slide),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.rs(10),
            vertical: context.rs(5),
          ),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : AppColors.paleGreen,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.28)
                  : AppColors.primaryGreen.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                page.badgeIcon,
                size: context.rs(13),
                color: isDark ? Colors.white : AppColors.primaryGreen,
              ),
              SizedBox(width: context.rs(6)),
              Flexible(
                child: Text(
                  page.badgeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: context.rs(11),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isDark ? Colors.white : AppColors.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                    ? Colors.white.withValues(alpha: 0.8)
                    : AppColors.textSecondary,
                fontSize: context.rs(16),
                fontWeight: FontWeight.w400,
                height: 1.25,
              ),
            ),
            SizedBox(height: context.rs(4)),
            Text(
              page.subtitle,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : AppColors.primaryGreen,
                fontSize: context.rs(34),
                fontWeight: FontWeight.w800,
                height: 1.12,
                letterSpacing: -1.0,
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
            begin: Offset(0, 0.08 * (e.key + 1)),
            end: Offset.zero,
          ).animate(slide),
          child: Padding(
            padding: EdgeInsets.only(bottom: context.rs(10)),
            child: Row(
              children: [
                Container(
                  width: context.rs(26),
                  height: context.rs(26),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : AppColors.paleGreen,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : AppColors.primaryGreen.withValues(alpha: 0.25),
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
                          ? Colors.white.withValues(alpha: 0.92)
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
      width: context.rs(76),
      height: context.rs(76),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.primaryGreen.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.28)
              : AppColors.primaryGreen.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : AppColors.primaryGreen.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: context.rs(36),
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
                colors: [Colors.transparent, Color(0xFF144D17)],
              )
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white],
              ),
      ),
      padding: EdgeInsets.fromLTRB(
        context.horizontalPadding,
        context.rs(16),
        context.horizontalPadding,
        MediaQuery.of(context).padding.bottom + context.rs(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dot indicators
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_pages.length, (i) {
              final isActive = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                margin: EdgeInsets.only(right: context.rs(5)),
                width: isActive ? context.rs(22) : context.rs(7),
                height: context.rs(7),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? Colors.white : AppColors.primaryGreen)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : AppColors.primaryGreen.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(width: 8),

          // Next / Mulai button
          Flexible(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _nextPage,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLast ? context.rs(20) : context.rs(16),
                    vertical: context.rs(12),
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.22)
                            : AppColors.primaryGreen.withValues(alpha: 0.38),
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isLast) ...[
                        Icon(
                          Icons.rocket_launch_rounded,
                          color: isDark ? AppColors.primaryGreen : Colors.white,
                          size: context.rs(17),
                        ),
                        SizedBox(width: context.rs(6)),
                      ],
                      Flexible(
                        child: Text(
                          isLast ? 'Mulai Sekarang' : 'Selanjutnya',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: isDark ? AppColors.primaryGreen : Colors.white,
                            fontSize: context.rs(13),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isLast) ...[
                        SizedBox(width: context.rs(6)),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: isDark ? AppColors.primaryGreen : Colors.white,
                          size: context.rs(15),
                        ),
                      ],
                    ],
                  ),
                ),
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
          color: Colors.white.withValues(alpha: 0.05),
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
          color: Colors.white.withValues(alpha: 0.04),
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
        painter: _DiagonalLinePainter(color: Colors.white.withValues(alpha: 0.04)),
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
          color: AppColors.primaryGreen.withValues(alpha: 0.06),
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
          color: AppColors.primaryGreen.withValues(alpha: 0.05),
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
