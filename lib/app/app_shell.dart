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
import '../features/settings/settings_screen.dart';
import '../shared/widgets/aurora_background.dart';
import '../shared/widgets/mini_player.dart';
import '../shared/widgets/rubber_dock.dart';
import 'tab_provider.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _tabs = <Widget>[
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    CreateScreen(),
    SettingsScreen(),
  ];

  static const _dockTabs = <RubberDockTab>[
    RubberDockTab(icon: Icons.home_rounded, label: 'Главная'),
    RubberDockTab(icon: Icons.search_rounded, label: 'Поиск'),
    RubberDockTab(icon: Icons.library_music_rounded, label: 'Медиатека'),
    RubberDockTab(icon: Icons.add_box_rounded, label: 'Создать'),
    RubberDockTab(icon: Icons.settings_rounded, label: 'Настройки'),
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

    final index = ref.watch(selectedTabProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: AppColors.backdrop,
        child: AuroraBackground(
          child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // IndexedStack сохраняет состояние вкладок и рисует только активную.
              Expanded(child: IndexedStack(index: index, children: _tabs)),
              // Мини-плеер один на все вкладки: стоит над доком, как только
              // загружен трек.
              MiniPlayer(
                onTap: track == null ? null : () => _openPlayer(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomInset),
                // Без карточки-панели: док занимает только свою высоту.
                child: RubberDock(
                  tabs: _dockTabs,
                  selected: index,
                  panelHeight: 1,
                  onSelected: ref.read(selectedTabProvider.notifier).select,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
