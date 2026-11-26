import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

class JellySlider extends StatefulWidget {
  const JellySlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onChanged,
    this.onChangeEnd,
    this.onPreview,
    this.labelBuilder,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  /// Позиция во время перетаскивания (перемотка выполняется только в
  /// [onChanged] при отпускании).
  final ValueChanged<Duration>? onPreview;

  /// Подпись на бегунке при перетаскивании; по умолчанию — таймкод.
  final String Function(Duration value)? labelBuilder;

  @override
  State<JellySlider> createState() => _JellySliderState();
}

class _JellySliderState extends State<JellySlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double? _dragValue;
  bool _dragging = false;

  /// После отпускания бегунок держится на цели, пока плеер перематывается.
  double? _hold;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  double get _maxMs =>
      widget.duration.inMilliseconds.clamp(1, 1 << 30).toDouble();

  double get _currentMs {
    final hold = _hold;
    var base = widget.position.inMilliseconds.toDouble();
    if (hold != null) {
      if ((base - hold).abs() < 1500 || DateTime.now().isAfter(_holdUntil)) {
        _hold = null;
      } else {
        base = hold;
      }
    }
    return (_dragValue ?? base).clamp(0, _maxMs).toDouble();
  }

  double get _progress => _currentMs / _maxMs;

  Duration get _currentDuration =>
      Duration(milliseconds: _currentMs.round());

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startDrag(Offset localPosition, double width) {
    setState(() {
      _dragging = true;
      _dragValue = _valueFromPosition(localPosition.dx, width);
    });

    _controller.forward();
    widget.onPreview?.call(_currentDuration);
  }

  void _updateDrag(Offset localPosition, double width) {
    if (!_dragging) return;

    setState(() {
      _dragValue = _valueFromPosition(localPosition.dx, width);
    });

    widget.onPreview?.call(_currentDuration);
  }

  void _endDrag() {
    if (!_dragging) return;

    final result = _currentDuration;

    setState(() {
      _dragging = false;
      _dragValue = null;
      _hold = result.inMilliseconds.toDouble();
      _holdUntil = DateTime.now().add(const Duration(milliseconds: 900));
    });

    _controller.reverse();
    widget.onChanged(result);
    widget.onChangeEnd?.call(result);
  }

  /// Отмена жеста без перемотки (тап перехвачен перетаскиванием и т.п.).
  void _abortDrag() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _dragValue = null;
    });
    _controller.reverse();
  }

  double _valueFromPosition(double x, double width) {
    const inset = 12.0;
    final available = (width - inset * 2).clamp(1.0, width);
    final normalized = ((x - inset) / available).clamp(0.0, 1.0);

    return normalized * _maxMs;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const inset = 12.0;
          const thumbSize = 24.0;
          const draggedSize = 46.0;
          const thumbBox = draggedSize;

          final available = (width - inset * 2).clamp(1.0, width);
          final thumbCenter = inset + available * _progress;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 68,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _startDrag(details.localPosition, width),
                  onTapUp: (_) => _endDrag(),
                  onTapCancel: _abortDrag,
                  onHorizontalDragStart: (details) =>
                      _startDrag(details.localPosition, width),
                  onHorizontalDragUpdate: (details) =>
                      _updateDrag(details.localPosition, width),
                  onHorizontalDragEnd: (_) => _endDrag(),
                  onHorizontalDragCancel: _abortDrag,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Track.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 29,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.22,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedContainer(
                              duration: _dragging
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: (thumbCenter - inset + 6)
                                  .clamp(0.0, width),
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Единственный бегунок: при перетаскивании растёт
                      // и показывает таймкод внутри себя.
                      Positioned(
                        left: thumbCenter - thumbBox / 2,
                        top: 32 - thumbBox / 2,
                        width: thumbBox,
                        height: thumbBox,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            width: _dragging ? draggedSize : thumbSize,
                            height: _dragging ? draggedSize : thumbSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.textPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.background.withValues(
                                  alpha: 0.12,
                                ),
                                width: 2,
                              ),
                            ),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 140),
                              opacity: _dragging ? 1 : 0,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    (widget.labelBuilder ?? formatDuration)(
                                      _currentDuration,
                                    ),
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: AppColors.background,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ],
          );
        },
      ),
    );
  }
}

/// Тот же бегунок, что и в плеере, для числового значения из диапазона
/// [min]..[max] с шагом [step] (масштаб текста и т.п.). Значение
/// применяется при отпускании, а подпись на бегунке показывает уже
/// округлённое до шага число.
class JellyValueSlider extends StatelessWidget {
  const JellyValueSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.labelBuilder,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final String Function(double value) labelBuilder;

  /// Разрешение внутренней шкалы: 10 000 делений на весь диапазон.
  static const _scale = 10000;

  /// Значение из позиции на шкале, округлённое до шага.
  double _valueAt(Duration position) {
    final fraction = (position.inMilliseconds / _scale).clamp(0.0, 1.0);
    final raw = min + fraction * (max - min);
    final snapped = min + ((raw - min) / step).round() * step;
    return (snapped.clamp(min, max) * 100).round() / 100;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return JellySlider(
      position: Duration(milliseconds: (fraction * _scale).round()),
      duration: const Duration(milliseconds: _scale),
      labelBuilder: (position) => labelBuilder(_valueAt(position)),
      onChanged: (position) => onChanged(_valueAt(position)),
    );
  }
}
