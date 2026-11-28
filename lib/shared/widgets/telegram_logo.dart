import 'package:flutter/material.dart';

/// Оригинальный логотип Telegram (круг с бумажным самолётиком), картинка из
/// `assets/images/telegram_logo.png`.
class TelegramLogo extends StatelessWidget {
  const TelegramLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/telegram_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Telegram',
    );
  }
}
