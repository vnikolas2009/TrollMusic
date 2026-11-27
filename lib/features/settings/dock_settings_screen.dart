import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dock_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/dock_layout.dart';

/// Настройка нижней панели: перетаскивайте вкладки, чтобы поменять порядок,
/// и выключайте ненужные. Настройки скрыть нельзя, видимых вкладок не меньше двух.
class DockSettingsScreen extends ConsumerWidget {
  const DockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(dockLayoutProvider);
    final ctl = ref.read(dockLayoutProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Нижняя панель'),
        actions: [
          TextButton(onPressed: ctl.reset, child: const Text('Сбросить')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Перетащите вкладку за значок справа, чтобы изменить порядок. '
              'Переключатель скрывает вкладку из панели.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: ReorderableListView(
              onReorder: ctl.reorder,
              children: [
                for (final id in layout.order)
                  ListTile(
                    key: ValueKey(id),
                    leading: Icon(dockTabInfos[id].icon),
                    title: Text(
                      dockTabInfos[id].label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    subtitle: id == dockSettingsTab
                        ? const Text('Всегда в панели')
                        : null,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 36),
                      child: Switch(
                        value: !layout.hidden.contains(id),
                        onChanged: id == dockSettingsTab ||
                                (!layout.hidden.contains(id) && !canHideTab(layout, id))
                            ? null
                            : (visible) => ctl.setHidden(id, !visible),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
