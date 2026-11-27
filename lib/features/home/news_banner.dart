import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/telegram_logo.dart';

/// Канал с новостями приложения.
final Uri newsChannelUrl = Uri.parse('https://t.me/TrollCerts');

/// Синяя плашка вверху главной: нажатие открывает канал в Telegram
/// (или в браузере, если приложения нет).
class NewsBanner extends StatelessWidget {
  const NewsBanner({super.key});

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(newsChannelUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: PressScale(
        scale: 0.98,
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2AABEE), Color(0xFF1C6FD6)],
            ),
          ),
          child: const Row(
            children: [
              TelegramLogo(
                size: 42,
                color: Colors.white,
                plane: Color(0xFF29A9EB),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Подпишись на TrollCerts, чтобы следить за новостями',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
