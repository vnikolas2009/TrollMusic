/// Нижняя панель: порядок и видимость вкладок.
///
/// Вкладки обозначаются номерами (`AppTab`): 0 главная, 1 поиск,
/// 2 медиатека, 3 импорт, 4 настройки.
const dockTabCount = 5;

/// Настройки скрыть нельзя: через них возвращаются скрытые вкладки.
const dockSettingsTab = 4;

/// В доке должно оставаться не меньше двух вкладок.
const dockMinVisible = 2;

typedef DockLayout = ({List<int> order, Set<int> hidden});

const defaultDockOrder = [0, 1, 2, 3, 4];

/// Приводит сохранённые значения к допустимому виду: порядок — перестановка
/// всех вкладок (повторы и неизвестные номера отбрасываются, недостающие
/// дописываются в конец), настройки видимы, видимых вкладок не меньше двух.
DockLayout normalizeDock(Iterable<int>? order, Iterable<int>? hidden) {
  final result = <int>[];
  for (final id in order ?? const <int>[]) {
    if (id >= 0 && id < dockTabCount && !result.contains(id)) result.add(id);
  }
  for (var id = 0; id < dockTabCount; id++) {
    if (!result.contains(id)) result.add(id);
  }

  final hide = <int>{
    for (final id in hidden ?? const <int>[])
      if (id >= 0 && id < dockTabCount && id != dockSettingsTab) id,
  };

  // Слишком много скрытых: возвращаем те, что стоят раньше в порядке.
  for (final id in result) {
    if (dockTabCount - hide.length >= dockMinVisible) break;
    hide.remove(id);
  }
  return (order: result, hidden: hide);
}

/// Видимые вкладки в порядке показа.
List<int> visibleDockTabs(DockLayout layout) =>
    [for (final id in layout.order) if (!layout.hidden.contains(id)) id];

/// Можно ли скрыть вкладку [id] (настройки и последние две — нельзя).
bool canHideTab(DockLayout layout, int id) =>
    id != dockSettingsTab &&
    !layout.hidden.contains(id) &&
    visibleDockTabs(layout).length > dockMinVisible;

/// Скрывает или показывает вкладку; запрещённые изменения игнорируются.
DockLayout setTabHidden(DockLayout layout, int id, bool hide) {
  final hidden = {...layout.hidden};
  if (hide) {
    if (!canHideTab(layout, id)) return layout;
    hidden.add(id);
  } else {
    hidden.remove(id);
  }
  return (order: layout.order, hidden: hidden);
}

/// Перемещает вкладку; индексы как в `ReorderableListView.onReorder`.
DockLayout reorderTabs(DockLayout layout, int oldIndex, int newIndex) {
  final order = [...layout.order];
  if (oldIndex < 0 || oldIndex >= order.length) return layout;
  var target = newIndex;
  if (target > oldIndex) target -= 1;
  target = target.clamp(0, order.length - 1);
  order.insert(target, order.removeAt(oldIndex));
  return (order: order, hidden: layout.hidden);
}
