import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/dock_layout.dart';

void main() {
  test('по умолчанию все вкладки видны в обычном порядке', () {
    final l = normalizeDock(null, null);
    expect(l.order, [0, 1, 2, 3, 4]);
    expect(l.hidden, isEmpty);
  });

  test('нормализация: повторы, неизвестные и недостающие вкладки', () {
    final l = normalizeDock([2, 2, 9, 0], null);
    expect(l.order, [2, 0, 1, 3, 4]);
  });

  test('настройки нельзя скрыть, лишние номера игнорируются', () {
    final l = normalizeDock(null, [4, 7, 1]);
    expect(l.hidden, {1});
  });

  test('не меньше двух видимых вкладок', () {
    final l = normalizeDock(null, [0, 1, 2, 3]);
    expect(visibleDockTabs(l).length, greaterThanOrEqualTo(dockMinVisible));
    expect(visibleDockTabs(l).contains(dockSettingsTab), isTrue);
  });

  test('скрытие и показ', () {
    var l = normalizeDock(null, null);
    l = setTabHidden(l, 3, true);
    expect(visibleDockTabs(l), [0, 1, 2, 4]);
    l = setTabHidden(l, 3, false);
    expect(visibleDockTabs(l), [0, 1, 2, 3, 4]);
  });

  test('скрыть настройки или последние две вкладки нельзя', () {
    var l = normalizeDock(null, null);
    expect(canHideTab(l, dockSettingsTab), isFalse);
    expect(setTabHidden(l, dockSettingsTab, true).hidden, isEmpty);

    l = setTabHidden(l, 0, true);
    l = setTabHidden(l, 1, true);
    l = setTabHidden(l, 2, true);
    expect(visibleDockTabs(l), [3, 4]);
    expect(canHideTab(l, 3), isFalse);
    expect(setTabHidden(l, 3, true).hidden, {0, 1, 2});
  });

  test('перестановка как в ReorderableListView', () {
    final l = normalizeDock(null, null);
    expect(reorderTabs(l, 0, 3).order, [1, 2, 0, 3, 4]);
    expect(reorderTabs(l, 3, 0).order, [3, 0, 1, 2, 4]);
    expect(reorderTabs(l, 0, 5).order, [1, 2, 3, 4, 0]);
    expect(reorderTabs(l, 9, 0).order, l.order);
  });

  test('порядок хранит скрытые вкладки на своих местах', () {
    var l = normalizeDock([4, 3, 2, 1, 0], null);
    l = setTabHidden(l, 2, true);
    expect(l.order, [4, 3, 2, 1, 0]);
    expect(visibleDockTabs(l), [4, 3, 1, 0]);
  });
}
