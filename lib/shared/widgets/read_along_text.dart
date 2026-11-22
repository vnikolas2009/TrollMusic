import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion/spring.dart';
import '../../core/utils/read_along.dart';

/// «Read along»: строка читается слово за словом, за читаемым словом едет
/// пилюля, прочитанные слова становятся яркими.
///
/// Края пилюли — две отдельные пружины: передний быстрый, задний ленивый,
/// поэтому она растягивается в движении и садится обратно по ширине слова.
/// На переносе строки пилюля не скользит поперёк текста, а схлопывается
/// и раскрывается заново на новой строке.
///
/// Время не считает сама: позицию читаемого слова задаёт [progress] (`0..1`
/// по строке), поэтому виджет работает и с синхронизированным текстом
/// (прогресс из таймкодов LRC), и с любым другим источником.
class ReadAlongText extends StatefulWidget {
  const ReadAlongText({
    super.key,
    required this.text,
    required this.progress,
    required this.style,
    this.pillColor = Colors.white,
    this.onPillColor = Colors.black,
    this.dimColor = const Color(0x6BFFFFFF),
  });

  final String text;

  /// Доля строки `0..1`: определяет читаемое слово.
  final double progress;

  /// Стиль текста; цвет прочитанных слов берётся из него.
  final TextStyle style;

  /// Цвет пилюли и цвет слова на ней.
  final Color pillColor;
  final Color onPillColor;

  /// Цвет слов, до которых чтение ещё не дошло.
  final Color dimColor;

  @override
  State<ReadAlongText> createState() => _ReadAlongTextState();
}

class _ReadAlongTextState extends State<ReadAlongText>
    with SingleTickerProviderStateMixin {
  /// На сколько em пилюля выступает за слово с каждой стороны.
  static const _pad = 0.16;
  static const _pillHeight = 1.3;
  static const _pillRadius = 0.34;

  final _left = Spring(0, 520, 40);
  final _right = Spring(0, 520, 40);
  final _top = Spring(0, 600, 48);
  final _opacity = Spring(0, 300, 30);
  late final List<Spring> _springs = [_left, _right, _top, _opacity];

  final _repaint = ValueNotifier<int>(0);
  late final SpringLoop _loop = SpringLoop(this, _frame);

  List<ReadWord> _words = const [];
  List<Rect> _rects = const [];
  List<Color> _colors = const [];

  int _at = -1;
  double? _lineTop;
  bool _reduceMotion = false;

  // Ключ раскладки: пересчитываем её, только если он изменился.
  String? _layoutText;
  double _layoutWidth = -1;
  TextScaler _layoutScaler = TextScaler.noScaling;
  TextStyle? _layoutStyle;

  @override
  void initState() {
    super.initState();
    _loop.start();
  }

  @override
  void dispose() {
    _loop.dispose();
    _repaint.dispose();
    super.dispose();
  }

  double get _fontSize => widget.style.fontSize ?? 14;

  Color _targetColor(int index) {
    if (index < _at) return widget.style.color ?? widget.pillColor;
    if (index == _at) return widget.onPillColor;
    return widget.dimColor;
  }

  TextSpan _span() {
    final text = widget.text;
    final children = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < _words.length; i++) {
      final word = _words[i];
      if (word.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, word.start)));
      }
      children.add(
        TextSpan(
          text: word.text,
          style: TextStyle(color: i < _colors.length ? _colors[i] : null),
        ),
      );
      cursor = word.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: widget.style, children: children);
  }

  void _layout(double width, TextScaler scaler) {
    final changed = _layoutText != widget.text ||
        _layoutWidth != width ||
        _layoutScaler != scaler ||
        _layoutStyle != widget.style;
    if (changed) {
      _layoutText = widget.text;
      _layoutWidth = width;
      _layoutScaler = scaler;
      _layoutStyle = widget.style;

      _words = splitWords(widget.text);
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: width);

      _rects = [
        for (final word in _words)
          _firstBox(painter, word),
      ];
      painter.dispose();
    }

    final at = wordIndexForProgress(_words, widget.progress);
    if (_colors.length != _words.length) {
      _at = at;
      _colors = [for (var i = 0; i < _words.length; i++) _targetColor(i)];
      _lineTop = null;
      _show();
    } else if (at != _at || changed) {
      _at = at;
      _show();
    }
  }

  Rect _firstBox(TextPainter painter, ReadWord word) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    if (boxes.isEmpty) return Rect.zero;
    final box = boxes.first;
    return Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
  }

  /// Новая цель пилюли для читаемого слова [_at].
  void _show() {
    if (_at < 0 || _at >= _rects.length) {
      _opacity.t = 0;
      return;
    }

    final box = _rects[_at];
    final pad = _fontSize * _pad;
    final l = box.left - pad;
    final r = box.right + pad;
    final top = box.top + (box.height - _fontSize * _pillHeight) / 2;

    _opacity.t = 1;
    final forward = l >= _left.t;

    if (_lineTop == null || (top - _lineTop!).abs() > 2 || _opacity.x < 0.05) {
      // Новая строка (или первое слово): раскрываемся с левого края слова.
      _left
        ..x = l
        ..t = l;
      _right.x = l;
      _top
        ..x = top
        ..t = top;
    }
    _lineTop = top;

    // Край по ходу движения быстрый, отстающий ленивый: отсюда растяжение.
    (forward ? _right : _left)
        .tune(SpringTokens.readLead, reduceMotion: _reduceMotion);
    (forward ? _left : _right)
        .tune(SpringTokens.readTrail, reduceMotion: _reduceMotion);

    _left.t = l;
    _right.t = r;
    _top.t = top;
  }

  void _frame(double dt) {
    stepSprings(_springs, dt);

    // Цвет слова плавно переходит к цели (≈0,18 с, как `transition: color`).
    final factor = 1 - math.exp(-dt / 0.07);
    var changed = false;
    for (var i = 0; i < _colors.length; i++) {
      final target = _targetColor(i);
      final current = _colors[i];
      if (current == target) continue;

      var next = Color.lerp(current, target, factor)!;
      final distance = (next.a - target.a).abs() +
          (next.r - target.r).abs() +
          (next.g - target.g).abs() +
          (next.b - target.b).abs();
      if (distance < 0.01) next = target;

      _colors[i] = next;
      changed = true;
    }

    if (changed && mounted) setState(() {});
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 10000.0;
        _layout(width, scaler);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PillPainter(
                    left: _left,
                    right: _right,
                    top: _top,
                    opacity: _opacity,
                    color: widget.pillColor,
                    height: _fontSize * _pillHeight,
                    radius: _fontSize * _pillRadius,
                    repaint: _repaint,
                  ),
                ),
              ),
            ),
            // Для скринридера строка читается целиком, а не по словам.
            Semantics(
              label: widget.text,
              excludeSemantics: true,
              child: RichText(
                text: _span(),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                strutStyle: StrutStyle.disabled,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PillPainter extends CustomPainter {
  _PillPainter({
    required this.left,
    required this.right,
    required this.top,
    required this.opacity,
    required this.color,
    required this.height,
    required this.radius,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Spring left;
  final Spring right;
  final Spring top;
  final Spring opacity;
  final Color color;
  final double height;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = opacity.x.clamp(0.0, 1.0).toDouble();
    if (alpha <= 0.001) return;

    final width = math.max(0.0, right.x - left.x);
    if (width <= 0) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left.x, top.x, width, height),
        Radius.circular(radius),
      ),
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }

  @override
  bool shouldRepaint(_PillPainter old) =>
      old.color != color || old.height != height || old.radius != radius;
}
