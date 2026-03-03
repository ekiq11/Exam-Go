import 'package:flutter/material.dart';

/// Responsive scaling helpers.
///
/// Rentang device yang didukung:
/// - Android kecil (320dp lebar) — misal Redmi 9A, Galaxy A01
/// - Android normal (360–414dp) — mayoritas Android
/// - iPhone SE / mini (375dp)
/// - iPhone standar (390–430dp)
/// - Android/iPhone besar (>430dp)
/// - Tablet 7–10 inch (600–800dp shortestSide)
extension ResponsiveContext on BuildContext {
  /// shortestSide ÷ 360 — clamp agar tidak terlalu besar/kecil
  /// Rentang: 0.85 (layar mungil) → 1.4 (tablet)
  double get _scale =>
      (MediaQuery.of(this).size.shortestSide / 360.0).clamp(0.85, 1.40);

  /// Skala font / padding / icon size
  double rs(double base) => base * _scale;

  /// Lebar layar
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Tinggi layar
  double get screenHeight => MediaQuery.of(this).size.height;

  /// True jika tablet (shortestSide >= 600dp)
  bool get isTablet => MediaQuery.of(this).size.shortestSide >= 600;

  /// True jika layar kecil (shortestSide <= 360dp)
  bool get isSmallPhone => MediaQuery.of(this).size.shortestSide <= 360;

  /// Padding horizontal yang proporsional:
  /// - Phone: 20dp ter-skala
  /// - Tablet: maks 40dp, dengan margin sisi lebih lebar
  double get horizontalPadding => isTablet ? rs(40) : rs(20);

  /// Lebar konten maksimum di tablet agar tidak terlalu melebar
  double get contentMaxWidth => isTablet ? 600.0 : double.infinity;
}

/// Wrapper untuk membatasi lebar konten di tablet
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const MaxWidthBox({super.key, required this.child, this.maxWidth = 600});

  @override
  Widget build(BuildContext context) {
    if (!context.isTablet) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
