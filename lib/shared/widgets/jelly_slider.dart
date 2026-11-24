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
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration>? onChangeEnd;

  /// Позиция во время перетаскивания (перемотка выполняется только в
  /// [onChanged] при отпускании).
  final ValueChanged<Duration>? onPreview;

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
          const bubbleSize = 42.0;

          final available = (width - inset * 2).clamp(1.0, width);
          final thumbCenter = inset + available * _progress;
          final bubbleLeft = (thumbCenter - bubbleSize / 2)
              .clamp(0.0, (width - bubbleSize).clamp(0.0, width));

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

                      // Bubble.
                      Positioned(
                        left: bubbleLeft,
                        top: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: _dragging ? 1 : 0,
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            scale: _dragging ? 1 : 0.65,
                            child: Container(
                              width: bubbleSize,
                              height: bubbleSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.textPrimary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                formatDuration(_currentDuration),
                                style: TextStyle(
                                  color: AppColors.background,
                                  fontSize: 9,
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

                      // Thumb.
                      Positioned(
                        left: thumbCenter - thumbSize / 2,
                        top: 20,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          scale: _dragging ? 1.16 : 1,
                          child: Container(
                            width: thumbSize,
                            height: thumbSize,
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
