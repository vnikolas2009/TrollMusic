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
import '../core/utils/dock_layout.dart';
import 'dock_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    ref.listen(audioErrorsProvider, (_, next) {
      final message = next.value;
      if (message == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });

    final selectedId = ref.watch(selectedTabProvider);
    final visible = visibleDockTabs(ref.watch(dockLayoutProvider));
    // Если выбранную вкладку скрыли, показываем первую из видимых.
    final current = visible.contains(selectedId) ? selectedId : visible.first;
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
              Expanded(
                child: IndexedStack(
                  index: visible.indexOf(current),
                  children: [
                    for (final id in visible)
                      KeyedSubtree(key: ValueKey(id), child: _tabs[id]),
                  ],
                ),
              ),
              // Мини-плеер один на все вкладки: стоит над доком, как только
              // загружен трек.
              MiniPlayer(
                onTap: () => openPlayerScreen(context),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + bottomInset),
                // Без карточки-панели: док занимает только свою высоту.
                child: RubberDock(
                  // Состав или порядок вкладок изменился — док собирается заново.
                  key: ValueKey(visible.join(',')),
                  tabs: [for (final id in visible) dockTabInfos[id]],
                  selected: visible.indexOf(current),
                  panelHeight: 1,
                  onSelected: (position) => ref
                      .read(selectedTabProvider.notifier)
                      .select(visible[position]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
