import 'package:flutter/painting.dart';

/// Стиль показа текста песни. Сохраняется по [name]; по умолчанию
/// [spotify].
enum LyricsStyle {
  /// Крупные строки: текущая яркая с подсветкой по словам, пройденные и
  /// будущие приглушены.
  spotify('Spotify-like', 'Текущая строка яркая, остальные приглушены'),

  /// Мелкий лёгкий текст, текущая строка чуть заметнее.
  minimal('Minimal', 'Спокойный текст с небольшим выделением строки'),

  /// Обычный читаемый текст, текущая строка подсвечена акцентным цветом.
  classic('Classic', 'Обычный текст с подсветкой текущей строки');

  const LyricsStyle(this.title, this.description);

  final String title;
  final String description;

  static const defaultStyle = LyricsStyle.spotify;

  /// Стиль по сохранённому имени; неизвестное значение даёт стиль по
  /// умолчанию.
  static LyricsStyle fromName(String? name) => LyricsStyle.values.firstWhere(
        (s) => s.name == name,
        orElse: () => defaultStyle,
      );

  LyricLook get look => switch (this) {
        LyricsStyle.spotify => const LyricLook(
            fontSize: 28,
            weight: FontWeight.w800,
            activeWeight: FontWeight.w800,
            verticalPadding: 10,
            inactiveScale: 0.94,
            wordHighlight: true,
            accentActive: false,
          ),
        LyricsStyle.minimal => const LyricLook(
            fontSize: 20,
            weight: FontWeight.w500,
            activeWeight: FontWeight.w700,
            verticalPadding: 8,
            inactiveScale: 1,
            wordHighlight: false,
            accentActive: false,
          ),
        LyricsStyle.classic => const LyricLook(
            fontSize: 22,
            weight: FontWeight.w500,
            activeWeight: FontWeight.w700,
            verticalPadding: 7,
            inactiveScale: 1,
            wordHighlight: false,
            accentActive: true,
          ),
      };

  /// Яркость строки по расстоянию до текущей (0 — текущая, меньше нуля —
  /// пройденные). Текущая всегда полностью яркая.
  double opacity(int distance) {
    if (distance == 0) return 1.0;
    final far = distance.abs() - 1;
    return switch (this) {
      // пройденные ярче будущих, дальние постепенно тускнеют
      LyricsStyle.spotify => distance < 0
          ? (0.55 - far * 0.04).clamp(0.3, 0.55).toDouble()
          : (0.38 - far * 0.02).clamp(0.24, 0.38).toDouble(),
      LyricsStyle.minimal => distance < 0 ? 0.45 : 0.38,
      LyricsStyle.classic => 0.82,
    };
  }
}

/// Размеры и начертание строк для выбранного [LyricsStyle].
class LyricLook {
  const LyricLook({
    required this.fontSize,
    required this.weight,
    required this.activeWeight,
    required this.verticalPadding,
    required this.inactiveScale,
    required this.wordHighlight,
    required this.accentActive,
  });

  final double fontSize;
  final FontWeight weight;
  final FontWeight activeWeight;
  final double verticalPadding;

  /// Масштаб неактивных строк (у текущей всегда 1).
  final double inactiveScale;

  /// Подсвечивать ли слова текущей строки по мере звучания.
  final bool wordHighlight;

  /// Красить ли текущую строку акцентным цветом.
  final bool accentActive;

  TextStyle textStyle({
    required bool active,
    required Color accent,
    double scale = 1.0,
  }) =>
      TextStyle(
        fontSize: fontSize * scale,
        height: 1.25,
        fontWeight: active ? activeWeight : weight,
        color: active && accentActive ? accent : const Color(0xFFFFFFFF),
      );
}
