import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/dock_layout.dart';
import '../shared/widgets/rubber_dock.dart';
import 'settings_provider.dart';

/// Описание вкладок дока по номерам `AppTab`.
const dockTabInfos = <RubberDockTab>[
  RubberDockTab(icon: Icons.home_rounded, label: 'Главная'),
  RubberDockTab(icon: Icons.search_rounded, label: 'Поиск'),
  RubberDockTab(icon: Icons.library_music_rounded, label: 'Медиатека'),
  RubberDockTab(icon: Icons.download_rounded, label: 'Импорт'),
  RubberDockTab(icon: Icons.settings_rounded, label: 'Настройки'),
];

/// Порядок и видимость вкладок нижней панели. Сохраняется в настройках.
class DockLayoutController extends Notifier<DockLayout> {
  @override
  DockLayout build() {
    final s = ref.read(settingsProvider);
    return normalizeDock(s.dockOrder, s.dockHidden);
  }

  void _set(DockLayout layout) {
    final s = ref.read(settingsProvider);
    s.dockOrder = layout.order;
    s.dockHidden = layout.hidden.toList()..sort();
    state = layout;
  }

  void reorder(int oldIndex, int newIndex) =>
      _set(reorderTabs(state, oldIndex, newIndex));

  void setHidden(int id, bool hidden) => _set(setTabHidden(state, id, hidden));

  void reset() => _set(normalizeDock(null, null));
}

final dockLayoutProvider =
    NotifierProvider<DockLayoutController, DockLayout>(DockLayoutController.new);
