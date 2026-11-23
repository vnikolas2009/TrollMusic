import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/app/tab_provider.dart';

void main() {
  test('вкладка по умолчанию — главная, индексы вне диапазона игнорируются', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(selectedTabProvider), AppTab.home);

    c.read(selectedTabProvider.notifier).select(AppTab.settings);
    expect(c.read(selectedTabProvider), AppTab.settings);

    c.read(selectedTabProvider.notifier).select(99);
    c.read(selectedTabProvider.notifier).select(-1);
    expect(c.read(selectedTabProvider), AppTab.settings);
  });
}
