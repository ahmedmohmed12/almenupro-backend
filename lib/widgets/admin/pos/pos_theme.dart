import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Visual tokens for the space-optimized POS cashier experience.
abstract final class PosTheme {
  /// Warm beige workspace background (brand surface).
  static const bg = AppTheme.brandBackground;
  static const surface = Colors.white;
  static const surfaceAlt = AppTheme.brandSurface;
  static const border = Color(0xFFE5D9CF);
  static const textMuted = Color(0xFF6B5B52);
  static const accent = AppTheme.brandMaroon;
  static const accentSoft = Color(0xFFF8EDE8);
  static const success = Color(0xFF16A34A);
  static const quickStrip = Color(0xFFFFF4E8);

  static const cartWidth = 380.0;
  static const categorySidebarWidth = 152.0;
  static const breakpoint = 1100.0;

  /// Compact action / platform chip height.
  static const compactChipHeight = 34.0;

  static BoxDecoration card({Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      );
}
