import 'package:flutter/material.dart';

/// Логотип Telegram: бумажный самолётик цвета [plane] в круге цвета [color].
class TelegramLogo extends StatelessWidget {
  const TelegramLogo({
    super.key,
    this.size = 40,
    this.color = const Color(0xFF29A9EB),
    this.plane = Colors.white,
  });

  final double size;
  final Color color;
  final Color plane;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TelegramPainter(color, plane)),
    );
  }
}

class _TelegramPainter extends CustomPainter {
  const _TelegramPainter(this.color, this.plane);

  final Color color;
  final Color plane;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, Paint()..color = color);

    Offset p(double x, double y) => Offset(x * s, y * s);

    // Корпус самолётика.
    final body = Path()
      ..moveTo(p(0.22, 0.49).dx, p(0.22, 0.49).dy)
      ..lineTo(p(0.76, 0.28).dx, p(0.76, 0.28).dy)
      ..cubicTo(p(0.80, 0.27).dx, p(0.80, 0.27).dy, p(0.83, 0.29).dx,
          p(0.83, 0.29).dy, p(0.82, 0.33).dx, p(0.82, 0.33).dy)
      ..lineTo(p(0.72, 0.72).dx, p(0.72, 0.72).dy)
      ..cubicTo(p(0.71, 0.76).dx, p(0.71, 0.76).dy, p(0.68, 0.77).dx,
          p(0.68, 0.77).dy, p(0.65, 0.75).dx, p(0.65, 0.75).dy)
      ..lineTo(p(0.52, 0.65).dx, p(0.52, 0.65).dy)
      ..lineTo(p(0.45, 0.72).dx, p(0.45, 0.72).dy)
      ..cubicTo(p(0.43, 0.74).dx, p(0.43, 0.74).dy, p(0.41, 0.74).dx,
          p(0.41, 0.74).dy, p(0.41, 0.71).dx, p(0.41, 0.71).dy)
      ..lineTo(p(0.42, 0.60).dx, p(0.42, 0.60).dy)
      ..lineTo(p(0.23, 0.53).dx, p(0.23, 0.53).dy)
      ..cubicTo(p(0.20, 0.52).dx, p(0.20, 0.52).dy, p(0.20, 0.50).dx,
          p(0.20, 0.50).dy, p(0.22, 0.49).dx, p(0.22, 0.49).dy)
      ..close();
    canvas.drawPath(body, Paint()..color = plane);

    // Складка: тёмная линия от центра к хвосту.
    final fold = Path()
      ..moveTo(p(0.42, 0.60).dx, p(0.42, 0.60).dy)
      ..lineTo(p(0.70, 0.36).dx, p(0.70, 0.36).dy)
      ..lineTo(p(0.52, 0.65).dx, p(0.52, 0.65).dy)
      ..close();
    canvas.drawPath(fold, Paint()..color = Colors.black.withValues(alpha: 0.14));
  }

  @override
  bool shouldRepaint(_TelegramPainter old) => old.color != color || old.plane != plane;
}
