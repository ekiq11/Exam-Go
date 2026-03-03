import 'package:flutter/material.dart';

/// Responsive scaling helpers — use everywhere instead of hard-coded sizes.
extension ResponsiveContext on BuildContext {
  double get _scale =>
      (MediaQuery.of(this).size.shortestSide / 360.0).clamp(0.85, 1.35);

  double rs(double base) => base * _scale; // font / padding / icon size
}
