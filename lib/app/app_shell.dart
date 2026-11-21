import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_motion.dart';
import '../features/create/create_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../shared/widgets/mini_player.dart';
import '../shared/widgets/troll_bottom_nav.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    CreateScreen(),
  ];

  void _openPlayer(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider).value;

    ref.listen(audioErrorsProvider, (_, next) {
      final message = next.value;
      if (message == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: AppColors.backdrop,
        child: SafeArea(
          bottom: false,
          // IndexedStack сохраняет состояние вкладок и рисует только активную.
          child: IndexedStack(index: _index, children: _tabs),
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(
            onTap: track == null ? null : () => _openPlayer(context),
          ),
          TrollBottomNav(
            index: _index,
            onChanged: (i) {
              if (i == _index) return;
              setState(() => _index = i);
            },
          ),
        ],
      ),
    );
  }
}
