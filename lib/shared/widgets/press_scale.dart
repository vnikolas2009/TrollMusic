import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

/// Обёртка для «магнитного» нажатия: лёгкое сжатие + возврат пружиной.
///
/// Анимируется только transform, поэтому всё остаётся на GPU.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool enabled;
  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    if (!interactive) return widget.child;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return GestureDetector(
        behavior: widget.behavior,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: widget.child,
      );
    }
    final active = _pressed && widget.enabled;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: active ? AppMotion.instant : AppMotion.base,
        curve: active ? AppMotion.exit : AppMotion.press,
        child: widget.child,
      ),
    );
  }
}
