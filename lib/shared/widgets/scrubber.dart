import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/seek_math.dart';

/// Ползунок таймкода плеера.
///
/// Что исправлено по сравнению с обычным `Slider`:
/// * `onSeek` вызывается **один раз** — при отпускании или тапе, а не на
///   каждый тик перетаскивания (раньше каждый тик гонял `seek` в плеер);
/// * пока палец на полосе, бегунок идёт за пальцем, а не за потоком позиции,
///   поэтому он не дёргается;
/// * после отпускания бегунок ещё ~0,9 с «держится» на целевой позиции, пока
///   плеер не закончит перемотку, и не отскакивает назад;
/// * у бегунка есть видимая ручка, полоса докачанного буфера и подсказка
///   с временем над ручкой;
/// * полоса и ручка пружинисто увеличиваются при нажатии.
///
/// Виджет не слушает `positionProvider` сам: позицию ему передаёт узкий
/// родитель (`_SeekBar`), чтобы остальной экран не перестраивался.
class Scrubber extends StatefulWidget {
  const Scrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.buffered = Duration.zero,
    this.onScrub,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// Вызывается при отпускании или тапе с целевой позицией.
  final ValueChanged<Duration> onSeek;

  /// Позиция предпросмотра во время перетаскивания; `null` — жест закончен.
  final ValueChanged<Duration?>? onScrub;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber>
    with SingleTickerProviderStateMixin {
  static const _barHeight = 36.0;
  static const _bubbleWidth = 58.0;
  static const _bubbleHeight = 26.0;
  static const _holdFor = Duration(milliseconds: 900);

  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: AppMotion.base,
    reverseDuration: AppMotion.fast,
  );
  late final Animation<double> _grow = CurvedAnimation(
    parent: _press,
    curve: AppMotion.press,
    reverseCurve: AppMotion.exit,
  );

  double _width = 1;

  /// Доля под пальцем; `null`, если ползунок не трогают.
  double? _drag;
  bool _dragging = false;

  /// Целевая доля после отпускания, пока плеер перематывается.
  double? _hold;
  DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  double _positionFraction() => fractionOf(widget.position, widget.duration);

  double _shownFraction() {
    final drag = _drag;
    if (drag != null) return drag;

    final hold = _hold;
    if (hold != null) {
      final current = _positionFraction();
      final settled = (current - hold).abs() < 0.015;
      if (settled || DateTime.now().isAfter(_holdUntil)) {
        _hold = null;
      } else {
        return hold;
      }
    }
    return _positionFraction();
  }

  void _begin(double dx) {
    if (widget.duration <= Duration.zero) return;
    final alreadyPressed = _drag != null;
    _update(dx);
    _press.forward();
    if (!alreadyPressed) HapticFeedback.selectionClick();
  }

  void _update(double dx) {
    if (widget.duration <= Duration.zero) return;
    final fraction = fractionForDx(dx, _width);
    setState(() => _drag = fraction);
    widget.onScrub?.call(durationForFraction(fraction, widget.duration));
  }

  void _commit() {
    final fraction = _drag;
    if (fraction == null) return;
    _hold = fraction;
    _holdUntil = DateTime.now().add(_holdFor);
    setState(() => _drag = null);
    _press.reverse();
    widget.onScrub?.call(null);
    widget.onSeek(durationForFraction(fraction, widget.duration));
    HapticFeedback.selectionClick();
  }

  void _abort() {
    if (_drag == null) return;
    setState(() => _drag = null);
    _press.reverse();
    widget.onScrub?.call(null);
  }

  void _nudge(Duration delta) {
    widget.onSeek(shiftPosition(widget.position, delta, widget.duration));
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = AppColors.surfaceHigh;
    final activeColor = AppColors.textPrimary;

    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1;

        final fraction = _shownFraction();
        final buffered = fractionOf(widget.buffered, widget.duration);
        final preview = durationForFraction(fraction, widget.duration);
        final bubbleLeft = (fraction * _width - _bubbleWidth / 2)
            .clamp(0.0, math.max(0.0, _width - _bubbleWidth))
            .toDouble();

        return Semantics(
          slider: true,
          label: 'Позиция воспроизведения',
          value: formatDuration(widget.position),
          increasedValue: formatDuration(
            shiftPosition(
              widget.position,
              const Duration(seconds: 10),
              widget.duration,
            ),
          ),
          decreasedValue: formatDuration(
            shiftPosition(
              widget.position,
              const Duration(seconds: -10),
              widget.duration,
            ),
          ),
          onIncrease: () => _nudge(const Duration(seconds: 10)),
          onDecrease: () => _nudge(const Duration(seconds: -10)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _begin(d.localPosition.dx),
            onTapUp: (_) => _commit(),
            // Когда перетаскивание «выигрывает» у тапа, приходит onTapCancel:
            // его нельзя считать отменой жеста, поэтому смотрим на флаг.
            onTapCancel: () {
              if (!_dragging) _abort();
            },
            onHorizontalDragStart: (d) {
              _dragging = true;
              _begin(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) => _update(d.localPosition.dx),
            onHorizontalDragEnd: (_) {
              _dragging = false;
              _commit();
            },
            onHorizontalDragCancel: () {
              _dragging = false;
              _abort();
            },
            child: SizedBox(
              height: _bubbleHeight + 8 + _barHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _barHeight,
                    child: AnimatedBuilder(
                      animation: _grow,
                      builder: (context, _) => CustomPaint(
                        painter: _ScrubberPainter(
                          fraction: fraction,
                          buffered: buffered,
                          grow: _grow.value,
                          active: activeColor,
                          track: trackColor,
                          bufferColor: activeColor.withValues(alpha: 0.2),
                          thumb: activeColor,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: bubbleLeft,
                    top: 0,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _grow,
                        builder: (context, _) {
                          final v = _grow.value.clamp(0.0, 1.0).toDouble();
                          return Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: Offset(0, (1 - v) * 8),
                              child: _TimeBubble(text: formatDuration(preview)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimeBubble extends StatelessWidget {
  const _TimeBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _ScrubberState._bubbleWidth,
      height: _ScrubberState._bubbleHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.inverse,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  const _ScrubberPainter({
    required this.fraction,
    required this.buffered,
    required this.grow,
    required this.active,
    required this.track,
    required this.bufferColor,
    required this.thumb,
  });

  final double fraction;
  final double buffered;

  /// Прогресс анимации нажатия; из-за пружинной кривой может чуть превышать 1.
  final double grow;
  final Color active;
  final Color track;
  final Color bufferColor;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final g = grow.clamp(0.0, 1.2).toDouble();
    final cy = size.height / 2;
    final h = ui.lerpDouble(4, 10, g)!;

    final trackRect = RRect.fromLTRBR(
      0,
      cy - h / 2,
      size.width,
      cy + h / 2,
      Radius.circular(h / 2),
    );

    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawRect(trackRect.outerRect, Paint()..color = track);
    if (buffered > 0) {
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          trackRect.top,
          size.width * buffered,
          trackRect.bottom,
        ),
        Paint()..color = bufferColor,
      );
    }
    canvas.drawRect(
      Rect.fromLTRB(0, trackRect.top, size.width * fraction, trackRect.bottom),
      Paint()..color = active,
    );
    canvas.restore();

    final radius = ui.lerpDouble(3.2, 9, g)!;
    final x = (size.width * fraction).clamp(0.0, size.width).toDouble();
    canvas.drawCircle(
      Offset(x, cy + 1.5),
      radius,
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(Offset(x, cy), radius, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_ScrubberPainter old) =>
      old.fraction != fraction ||
      old.buffered != buffered ||
      old.grow != grow ||
      old.active != active ||
      old.track != track ||
      old.bufferColor != bufferColor ||
      old.thumb != thumb;
}
