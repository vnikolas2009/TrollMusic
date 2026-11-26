import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/theme/app_colors.dart';
import '../features/create/create_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/mini_player.dart';
import '../shared/widgets/mini_player_bar.dart';
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
    RubberDockTab(icon: Icons.download_rounded, label: 'Импорт'),
    RubberDockTab(icon: Icons.settings_rounded, label: 'Настройки'),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(audioErrorsProvider, (_, next) {
      final message = next.value;
      if (message == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });

    final index = ref.watch(selectedTabProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: AppColors.backdrop,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // IndexedStack сохраняет состояние вкладок и рисует только активную.
              Expanded(child: IndexedStack(index: index, children: _tabs)),
              // Мини-плеер один на все вкладки: стоит над доком, как только
              // загружен трек.
              MiniPlayer(
                onTap: () => openPlayerScreen(context),
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
    );
  }
}
