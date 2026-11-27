import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/appearance_controller.dart';
import '../../app/lyrics_background_provider.dart';
import '../../app/lyrics_style_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/lyric_style.dart';
import '../../shared/widgets/scale_slider_tile.dart';
import '../../shared/widgets/spring_switch_tile.dart';

/// Все настройки, связанные с текстом песен: стиль, размер, строка под
/// обложкой. Открывается из экрана текста.
Future<void> showLyricsSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceAlt,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _LyricsSettingsSheet(),
  );
}

class _LyricsSettingsSheet extends ConsumerWidget {
  const _LyricsSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final lookCtl = ref.read(appearanceProvider.notifier);
    final style = ref.watch(lyricsStyleProvider);
    final bg = ref.watch(lyricsBackgroundProvider);
    final bgCtl = ref.read(lyricsBackgroundProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Настройки текста',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<LyricsStyle>(
                showSelectedIcon: false,
                segments: [
                  for (final s in LyricsStyle.values)
                    ButtonSegment(value: s, label: Text(s.title)),
                ],
                selected: {style},
                onSelectionChanged: (v) =>
                    ref.read(lyricsStyleProvider.notifier).set(v.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                style.description,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            ScaleSliderTile(
              title: 'Размер текста',
              value: look.lyricsScale,
              min: TextScaleRange.lyricsMin,
              max: TextScaleRange.lyricsMax,
              step: TextScaleRange.step,
              onChanged: lookCtl.setLyricsScale,
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.wallpaper_rounded),
              title: const Text(
                'Фон экрана текста',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                bg.fileName == null
                    ? 'PNG, JPG, WebP или GIF'
                    : 'Выбрана картинка',
              ),
              trailing: bg.path == null
                  ? null
                  : IconButton(
                      tooltip: 'Убрать фон',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: bgCtl.clear,
                    ),
              onTap: () async {
                try {
                  await bgCtl.pick();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Не удалось выбрать фон: $e')),
                    );
                  }
                }
              },
            ),
            if (bg.path != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Затемнение')),
                    ButtonSegment(value: true, label: Text('Градиент')),
                  ],
                  selected: {bg.gradient},
                  onSelectionChanged: (v) => bgCtl.setGradient(v.first),
                ),
              ),
              ScaleSliderTile(
                title: 'Сила затемнения',
                value: bg.dim,
                min: 0.2,
                max: 0.9,
                step: 0.05,
                onChanged: bgCtl.setDim,
              ),
              const SizedBox(height: 8),
            ],
            SpringSwitchTile(
              title: 'Строка текста под обложкой',
              subtitle: 'Текущая строка в плеере; нажатие открывает весь текст',
              value: look.showLyricPreview,
              onChanged: lookCtl.setShowLyricPreview,
            ),
          ],
        ),
      ),
    );
  }
}
