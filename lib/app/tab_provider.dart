import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Вкладки нижнего дока. Порядок = порядок кнопок в [RubberDock].
abstract final class AppTab {
  static const home = 0;
  static const search = 1;
  static const library = 2;
  static const create = 3;
  static const settings = 4;
  static const count = 5;
}

/// Текущая вкладка. Через провайдер любой экран может переключить вкладку
/// (например, карточка «Подключите VK» открывает настройки).
class SelectedTabController extends Notifier<int> {
  @override
  int build() => AppTab.home;

  void select(int index) {
    if (index < 0 || index >= AppTab.count || index == state) return;
    state = index;
  }
}

final selectedTabProvider =
    NotifierProvider<SelectedTabController, int>(SelectedTabController.new);
