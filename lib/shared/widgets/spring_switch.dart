import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/motion/spring.dart';
import '../../core/theme/app_colors.dart';

/// «Toggle switch»: ручка растягивается в сторону движения, потом
/// округляется и пружинит на месте, пока дорожка заливается цветом.
///
/// У каждого переключателя две пружины: позиция (320/18) и растяжение (300/20).
/// Переключение «пинает» растяжение, поэтому ручка вытягивается вперёд
/// и садится с лёгким отскоком.
class SpringSwitch extends StatefulWidget {
  const SpringSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.activeColor,
    this.inactiveColor,
  });

  final bool value;

  /// `null` отключает переключатель.
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  /// Цвет дорожки во включённом состоянии (по умолчанию акцент темы).
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  State<SpringSwitch> createState() => _SpringSwitchState();
}

class _SpringSwitchState extends State<SpringSwitch>
    with SingleTickerProviderStateMixin {
  static const _trackWidth = 52.0;
  static const _trackHeight = 32.0;
  static const _knob = 26.0;
  static const _inset = 3.0;
  static const _travel = 20.0;
  static const _maxGrow = 10.0;

  late final Spring _position = Spring(widget.value ? 1 : 0, 320, 18);
  late final Spring _stretch = Spring(0, 300, 20);
  late final SpringLoop _loop = SpringLoop(this, _frame);

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _loop.start();
  }

  @override
  void didUpdateWidget(SpringSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    _position.t = widget.value ? 1 : 0;
    _stretch
      ..t = 0
      ..v = 60;
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  void _frame(double dt) {
    stepSprings([_position, _stretch], dt);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _position.tune(SpringTokens.togglePosition, reduceMotion: _reduceMotion);
    _stretch.tune(SpringTokens.toggleStretch, reduceMotion: _reduceMotion);

    final progress = _position.x.clamp(0.0, 1.0).toDouble();
    final grow = _stretch.x.clamp(0.0, 1.0).toDouble() * _maxGrow;
    final x = _position.x * _travel;

    // Ручка растёт к месту назначения: при включении правый край впереди,
    // поэтому левый сдвигаем назад на величину растяжения.
    final shift = widget.value ? x - grow * progress : x;

    final enabled = widget.onChanged != null;
    final onColor = widget.activeColor ?? AppColors.accent;
    final offColor = widget.inactiveColor ?? AppColors.surfaceHigh;
    final track = Color.lerp(offColor, onColor, progress)!;

    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onChanged!(!widget.value);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(
            width: _trackWidth,
            height: _trackHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(_trackHeight / 2),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: _inset + shift,
                    top: _inset,
                    width: _knob + grow,
                    height: _knob,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(_knob / 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
