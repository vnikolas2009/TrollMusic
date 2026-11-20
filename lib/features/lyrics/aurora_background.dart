import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Медленно дрейфующие цветные «пятна» на тёмном фоне — окрашиваются в цвет обложки.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.color});

  final Color color;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 28))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: widget.color),
        duration: const Duration(milliseconds: 800),
        builder: (context, color, _) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _AuroraPainter(color ?? widget.color, _controller.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.base, this.t);

  final Color base;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF050505));

    final hsl = HSLColor.fromColor(base);
    final colors = [
      base,
      hsl.withHue((hsl.hue + 40) % 360).toColor(),
      hsl.withHue((hsl.hue + 320) % 360).toColor(),
    ];

    for (var i = 0; i < colors.length; i++) {
      final a = t * 2 * math.pi + i * 2.1;
      final center = Offset(
        size.width * (0.5 + 0.38 * math.cos(a * (1 + i * 0.3))),
        size.height * (0.35 + 0.3 * math.sin(a * (1 - i * 0.15) + i)),
      );
      final radius = size.shortestSide * (0.9 + 0.15 * i);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [colors[i].withValues(alpha: 0.55), colors[i].withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Затемнение для читаемости текста.
    canvas.drawRect(rect, Paint()..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t || old.base != base;
}
