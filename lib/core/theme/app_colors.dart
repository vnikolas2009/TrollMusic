import 'package:flutter/material.dart';

/// Палитра TrollMusic: чистый чёрный, нейтральные поверхности и один акцент.
abstract final class AppColors {
  static const background = Color(0xFF000000);

  static const surface = Color(0xFF0B0B0C);
  static const surfaceAlt = Color(0xFF141416);
  static const surfaceHigh = Color(0xFF1E1E21);
  static const surfaceMini = Color(0xFF19191C);

  static const accent = Color(0xFF1ED760);
  static const accentSoft = Color(0xFF8AF3B0);
  static const onAccent = Color(0xFF04170B);

  static const textPrimary = Color(0xFFF7F7F8);
  static const textSecondary = Color(0xFF9A9AA0);
  static const textTertiary = Color(0xFF6B6B72);

  static const divider = Color(0xFF26262A);

  /// Полупрозрачные слои для стекла и скримов.
  static const glass = Color(0xB3121214);
  static const glassStrong = Color(0xE60E0E10);
  static const glassBorder = Color(0x1FFFFFFF);
  static const glassHighlight = Color(0x14FFFFFF);
  static const scrim = Color(0xD9000000);

  /// Мягкое свечение акцента (тени, ореолы).
  static const accentGlow = Color(0x331ED760);
  static const shadow = Color(0x99000000);

  static const stationYellow = Color(0xFFF5D565);
  static const stationPink = Color(0xFFE89AC7);
  static const stationMint = Color(0xFF9BE0C4);
  static const stationLilac = Color(0xFFB9A7F5);
  static const stationPeach = Color(0xFFF2A97E);

  /// Затемняющий градиент поверх обложек.
  static const coverScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xB3000000)],
  );
}
