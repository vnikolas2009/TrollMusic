import 'package:flutter/material.dart';

import '../../core/theme/appearance.dart';

/// Статичный фон экрана текста: сплошной тёмный градиент в цвет обложки.
/// Яркость цвета ограничена, поэтому белый текст читается всегда (контраст > 7:1),
/// в любой теме приложения. Никакой анимации и blur — минимальная нагрузка на GPU.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final top = hsl
        .withLightness(hsl.lightness.clamp(0.12, 0.26).toDouble())
        .withSaturation(hsl.saturation.clamp(0.0, 0.6).toDouble())
        .toColor();
    // Интенсивность эффектов: при «Выкл» фон ровный тёмный, дальше цвет
    // обложки проступает сильнее (яркость и так ограничена ради контраста).
    const base = Color(0xFF0A0A0A);
    final tinted = Color.lerp(base, top, AppAppearance.fx.clamp(0.0, 1.0).toDouble())!;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tinted),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [value ?? tinted, base],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
