import 'dart:ui' show Offset;

import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Режим анимаций. Скорость задаётся через `timeDilation` (меньше — быстрее),
/// а [reduceMotion] включает то же поведение, что системная настройка
/// «убрать анимации»: пружины без перелёта, без бликов.
enum AnimationMode {
  smooth('Плавные', 'Все пружинные эффекты и переходы', 1.0, false),
  fast('Быстрые', 'Те же анимации, но заметно быстрее', 0.6, false),
  calm('Без отскока', 'Спокойные движения без пружинного перелёта и бликов', 1.0, true),
  minimal('Минимум', 'Короткие переходы без отскоков и бликов', 0.35, true);

  const AnimationMode(this.title, this.description, this.timeDilation, this.reduceMotion);

  final String title;
  final String description;

  /// Множитель времени: 1 — как задумано, меньше 1 — быстрее.
  final double timeDilation;

  final bool reduceMotion;

  static const defaultMode = AnimationMode.smooth;

  static AnimationMode byIndex(int? i) =>
      values[(i ?? defaultMode.index).clamp(0, values.length - 1)];
}

/// Интенсивность визуальных эффектов: тени и свечение под обложкой, подкраска
/// фона плеера и экрана текстов.
enum EffectsLevel {
  off('Выкл', 0.0),
  soft('Мягкие', 0.5),
  normal('Обычные', 1.0),
  vivid('Яркие', 1.5);

  const EffectsLevel(this.title, this.factor);

  final String title;
  final double factor;

  static const defaultLevel = EffectsLevel.normal;

  static EffectsLevel byIndex(int? i) =>
      values[(i ?? defaultLevel.index).clamp(0, values.length - 1)];
}

/// Форма обложек: коэффициент к базовому радиусу скругления.
enum CoverShape {
  square('Квадратные', 0.0),
  rounded('Скруглённые', 1.0),
  soft('Мягкие', 2.2);

  const CoverShape(this.title, this.factor);

  final String title;
  final double factor;

  static const defaultShape = CoverShape.rounded;

  static CoverShape byIndex(int? i) =>
      values[(i ?? defaultShape.index).clamp(0, values.length - 1)];
}

/// Диапазоны ползунков размера текста.
abstract final class TextScaleRange {
  static const interfaceMin = 0.85;
  static const interfaceMax = 1.2;
  static const lyricsMin = 0.85;
  static const lyricsMax = 1.4;
  static const step = 0.05;
}

/// Текущие косметические настройки, доступные виджетам напрямую (как
/// [AppColors]). Значения выставляет `AppearanceController`; после смены всё
/// дерево пересобирается.
abstract final class AppAppearance {
  static EffectsLevel effects = EffectsLevel.defaultLevel;
  static CoverShape coverShape = CoverShape.defaultShape;

  static double get fx => effects.factor;

  /// Радиус скругления обложки с учётом выбранной формы.
  static double coverRadius(double base) => base * coverShape.factor;

  /// Тень с учётом интенсивности эффектов: при «Выкл» тени нет, иначе
  /// растут прозрачность и размытие.
  static List<BoxShadow> shadows({
    required double blur,
    required Offset offset,
  }) {
    if (fx <= 0) return const [];
    final base = AppColors.shadow;
    return [
      BoxShadow(
        color: base.withValues(alpha: (base.a * fx).clamp(0.0, 1.0).toDouble()),
        blurRadius: blur * (0.6 + 0.4 * fx),
        offset: offset,
      ),
    ];
  }
}
