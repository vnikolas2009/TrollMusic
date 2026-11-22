import 'package:flutter/material.dart';

/// Набор цветов темы. Все поверхности сплошные: никакого blur/«стекла».
/// Подложки — сплошные цвета с лёгкой прозрачностью 0.9–0.95 и тонкой рамкой 1 px.
@immutable
class AppPalette {
  const AppPalette({
    required this.isDark,
    required this.gradient,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.surfaceMini,
    required this.cardStrong,
    required this.outline,
    required this.highlight,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.accentTint,
    required this.inverse,
    required this.shadow,
  });

  final bool isDark;

  /// Лёгкий градиент от акцента в верхней части экранов.
  final bool gradient;

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;

  /// Мини-плеер и навигация: сплошной цвет, прозрачность 0.95.
  final Color surfaceMini;
  final Color cardStrong;

  /// Тонкая рамка 1 px для карточек и панелей.
  final Color outline;
  final Color highlight;
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color accentTint;

  /// Цвет контента на заливке цветом `textPrimary` (кнопки, выбранные чипы).
  final Color inverse;
  final Color shadow;

  /// Текущая палитра. Обновляется в корне приложения перед сборкой дерева.
  static AppPalette current = AppPalette.build(
    brightness: Brightness.dark,
    accent: const Color(0xFF1ED760),
  );

  factory AppPalette.build({
    required Brightness brightness,
    required Color accent,
    bool amoled = false,
    bool gradient = true,
  }) {
    final dark = brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(accent);
    final softLightness = dark ? hsl.lightness + 0.22 : hsl.lightness - 0.12;
    final soft = hsl.withLightness(softLightness.clamp(0.0, 1.0)).toColor();
    final onAccent = accent.computeLuminance() > 0.45
        ? const Color(0xFF0A0A0A)
        : const Color(0xFFFFFFFF);

    if (dark) {
      return AppPalette(
        isDark: true,
        gradient: gradient,
        background: amoled ? const Color(0xFF000000) : const Color(0xFF0A0A0A),
        surface: const Color(0xFF121212),
        surfaceAlt: const Color(0xFF1E1E1E),
        surfaceHigh: const Color(0xFF2A2A2A),
        surfaceMini: const Color(0xF2181818),
        cardStrong: const Color(0xF2121212),
        outline: const Color(0x1FFFFFFF),
        highlight: const Color(0x14FFFFFF),
        divider: const Color(0xFF262626),
        textPrimary: const Color(0xFFF5F5F5),
        textSecondary: const Color(0xFFA0A0A5),
        textTertiary: const Color(0xFF6E6E74),
        accent: accent,
        accentSoft: soft,
        onAccent: onAccent,
        accentTint: accent.withAlpha(0x33),
        inverse: const Color(0xFF000000),
        shadow: const Color(0x99000000),
      );
    }
    return AppPalette(
      isDark: false,
      gradient: gradient,
      background: const Color(0xFFF2F2F5),
      surface: const Color(0xFFFFFFFF),
      surfaceAlt: const Color(0xFFFFFFFF),
      surfaceHigh: const Color(0xFFE6E6EB),
      surfaceMini: const Color(0xF2FFFFFF),
      cardStrong: const Color(0xF2FFFFFF),
      outline: const Color(0x14000000),
      highlight: const Color(0x0F000000),
      divider: const Color(0xFFE0E0E5),
      textPrimary: const Color(0xFF111114),
      textSecondary: const Color(0xFF5E5E66),
      textTertiary: const Color(0xFF8E8E96),
      accent: accent,
      accentSoft: soft,
      onAccent: onAccent,
      accentTint: accent.withAlpha(0x2E),
      inverse: const Color(0xFFFFFFFF),
      shadow: const Color(0x33000000),
    );
  }

  /// Отпечаток для сравнения палитр.
  int get signature => Object.hash(
        isDark,
        gradient,
        background,
        accent,
        textPrimary,
      );
}

/// Доступ к цветам текущей темы. Значения читаются в момент сборки виджета,
/// поэтому при смене темы дерево пересобирается (см. `TrollMusicApp`).
abstract final class AppColors {
  static AppPalette get _p => AppPalette.current;

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceAlt => _p.surfaceAlt;
  static Color get surfaceHigh => _p.surfaceHigh;
  static Color get surfaceMini => _p.surfaceMini;

  static Color get accent => _p.accent;
  static Color get accentSoft => _p.accentSoft;
  static Color get onAccent => _p.onAccent;
  static Color get accentTint => _p.accentTint;

  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textTertiary => _p.textTertiary;

  static Color get divider => _p.divider;
  static Color get outline => _p.outline;
  static Color get cardStrong => _p.cardStrong;
  static Color get highlight => _p.highlight;
  static Color get shadow => _p.shadow;
  static Color get inverse => _p.inverse;

  static const scrim = Color(0xD9000000);

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

  /// Фон экранов: сплошной цвет или едва заметный градиент от акцента.
  static BoxDecoration get backdrop {
    if (!_p.gradient) return BoxDecoration(color: _p.background);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _p.accent.withAlpha(_p.isDark ? 0x26 : 0x22),
          _p.background,
        ],
        stops: const [0, 0.5],
      ),
    );
  }

  /// Фон закреплённого `SliverAppBar`.
  ///
  /// Пока контент не прокручен под панель, она полностью прозрачна и виден
  /// градиент [backdrop]. Раньше здесь был почти непрозрачный `background`,
  /// из-за чего верх экрана выглядел чёрной плашкой поверх градиента.
  /// Когда контент заезжает под панель (`scrolledUnder`), панель получает
  /// фон, чтобы заголовок оставался читаемым.
  static WidgetStateColor get appBarBackground => WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? _p.background.withValues(alpha: 0.94)
            : const Color(0x00000000),
      );

  /// Тон обложки для подложки экрана плеера: в тёмной теме — как есть,
  /// в светлой — мягкий оттенок, чтобы тёмный текст оставался читаемым.
  static Color tinted(Color cover) => _p.isDark
      ? cover
      : Color.lerp(_p.background, cover, 0.28) ?? _p.background;
}
