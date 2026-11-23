import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Медленно плывущее акцентное свечение за контентом. Три размытых пятна
/// двигаются по эллипсам; рисуется одним `CustomPainter` без размытия
/// (радиальные градиенты), поэтому почти ничего не стоит.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _AuroraPainter(
                animation: _controller,
                color: AppColors.accent,
                strength: AppPalette.current.isDark ? 0.09 : 0.06,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.animation,
    required this.color,
    required this.strength,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final double strength;

  /// Положение пятна `0..1` по осям для фазы [t] (`0..1`).
  static Offset blobCenter(double t, int index) {
    final a = (t + index / 3) * 2 * math.pi;
    final cx = 0.5 + 0.38 * math.cos(a + index);
    final cy = 0.5 + 0.34 * math.sin(a * (index.isEven ? 1 : 2) + index * 2);
    return Offset(cx, cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = animation.value;
    final radius = size.longestSide * 0.55;

    for (var i = 0; i < 3; i++) {
      final c = blobCenter(t, i);
      final center = Offset(c.dx * size.width, c.dy * size.height);
      final tint = i == 1
          ? Color.lerp(color, const Color(0xFFEC4899), 0.45)!
          : color;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: strength),
            tint.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.color != color || old.strength != strength;
}
