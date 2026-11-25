import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../features/player/player_screen.dart';
import 'mini_player.dart';

/// Открывает полноэкранный плеер с анимацией «выезда» снизу.
void openPlayerScreen(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: AppMotion.slower,
      reverseTransitionDuration: AppMotion.base,
      pageBuilder: (_, __, ___) => const PlayerScreen(),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.exit,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Мини-плеер для экранов, которые открываются поверх оболочки приложения
/// (плейлист, исполнитель, альбом). Ставится в `Scaffold.bottomNavigationBar`,
/// поэтому не перекрывает контент. Без трека занимает нулевую высоту.
class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: MiniPlayer(onTap: () => openPlayerScreen(context)),
    );
  }
}
