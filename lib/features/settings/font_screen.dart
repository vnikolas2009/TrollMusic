import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/font_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../services/fonts/font_service.dart';

/// Пример для предпросмотра: кириллица, латиница, цифры.
const _sample = 'Съешь же ещё этих мягких булок\nThe quick brown fox 0123456789';

/// Выбор шрифта: стандартный или импортированный TTF/OTF, предпросмотр
/// каждого варианта, удаление импортированных.
class FontScreen extends ConsumerWidget {
  const FontScreen({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(fontControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      dialogTitle: 'Выбрать шрифт',
    );
    final path = picked?.path;
    if (path == null) return;

    final PendingFont pending;
    try {
      pending = await controller.prepare(path);
    } on FontImportException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(pending.name),
        content: Text(
          _sample,
          style: TextStyle(fontFamily: pending.family, fontSize: 20, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Добавить и применить'),
          ),
        ],
      ),
    );
    if (accepted != true) return;

    try {
      await controller.addAndSelect(pending);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить шрифт')),
        );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    UserFont font,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить шрифт?'),
        content: Text(font.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(fontControllerProvider.notifier).remove(font.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fontControllerProvider);
    final controller = ref.read(fontControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Шрифт'),
        backgroundColor: AppColors.appBarBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _FontTile(
            title: 'Стандартный',
            selected: state.selectedId == null,
            onTap: controller.reset,
          ),
          for (final font in BuiltInFont.all)
            _FontTile(
              title: font.name,
              description: font.description,
              family: font.family,
              selected: state.selectedId == font.id,
              onTap: () => controller.select(font.id),
            ),
          for (final font in state.fonts)
            _FontTile(
              title: font.name,
              family: font.family,
              selected: state.selectedId == font.id,
              onTap: () => controller.select(font.id),
              onDelete: () => _confirmRemove(context, ref, font),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () => _import(context, ref),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Импортировать шрифт (TTF, OTF)'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              'Шрифт копируется в папку приложения. Выбор сохраняется после '
              'перезапуска; «Стандартный» возвращает исходный вид.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.family,
    this.description,
    this.onDelete,
  });

  final String title;

  /// Короткое описание характера шрифта.
  final String? description;

  /// Семейство для предпросмотра; `null` — стандартный шрифт.
  final String? family;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      title: Text(description == null ? title : '$title · $description'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _sample,
          style: TextStyle(
            fontFamily: family,
            fontSize: 16,
            height: 1.3,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete != null)
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
            ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? AppColors.accent : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
