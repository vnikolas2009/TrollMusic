import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// Мягкое появление элемента: fade + короткий сдвиг снизу.
///
/// [index] задаёт задержку, чтобы списки и секции раскрывались каскадом.
/// Анимация запускается один раз при первом появлении.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offsetY = 0.05,
    this.duration,
    this.delay,
  });

  final Widget child;
  final int index;
  final double offsetY;
  final Duration? duration;
  final Duration? delay;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration ?? AppMotion.slow,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.enter,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final step = widget.index.clamp(0, AppMotion.staggerMaxIndex).toInt();
    final delay = widget.delay ??
        Duration(milliseconds: AppMotion.staggerStep.inMilliseconds * step);
    _timer = Timer(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.offsetY),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
