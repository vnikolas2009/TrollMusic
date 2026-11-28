import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';

/// Кнопка «Нравится»: при добавлении в избранное сердце «подпрыгивает», а
/// вокруг разлетаются частицы. Без анимаций (системная настройка или режим
/// «минимум») меняется только значок.
class HeartButton extends StatefulWidget {
  const HeartButton({super.key, required this.liked, required this.onPressed});

  final bool liked;
  final VoidCallback onPressed;

  @override
  State<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<HeartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 50),
  ]).animate(_controller);

  @override
  void didUpdateWidget(HeartButton old) {
    super.didUpdateWidget(old);
    if (!old.liked && widget.liked && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => CustomPaint(
                size: const Size(48, 48),
                painter: _BurstPainter(_controller.isAnimating ? _controller.value : 0, AppColors.accent),
              ),
            ),
          ),
          ScaleTransition(
            scale: _scale,
            child: IconButton(
              onPressed: widget.onPressed,
              icon: Icon(
                widget.liked ? Icons.favorite : Icons.favorite_border,
                color: widget.liked ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final center = size.center(Offset.zero);
    final progress = Curves.easeOutCubic.transform(t);
    const count = 8;

    for (var i = 0; i < count; i++) {
      final angle = 2 * math.pi * i / count + math.pi / 8;
      final distance = 12 + 20 * progress;
      final radius = (i.isEven ? 3.0 : 2.0) * (1 - t);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * distance,
        radius,
        Paint()..color = color.withValues(alpha: (1 - t).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
