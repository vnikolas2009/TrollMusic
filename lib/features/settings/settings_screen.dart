import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lyrics_job.dart';
import '../../app/appearance_controller.dart';
import '../../app/font_controller.dart';
import '../../app/lyrics_style_provider.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../app/theme_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/lyric_style.dart';
import '../../shared/widgets/spring_switch.dart';
import '../../shared/widgets/spring_switch_tile.dart';
import 'font_screen.dart';
import '../../shared/widgets/tab_header.dart';
import 'storage_meter.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  StorageMeterData? _storageData;
  bool _loadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    try {
      final data = await StorageMeterData.load(ref.read(storageProvider));
      if (!mounted) return;
      setState(() {
        _storageData = data;
        _loadingCache = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = ref.watch(themeControllerProvider);
    final themeCtl = ref.read(themeControllerProvider.notifier);
    final look = ref.watch(appearanceProvider);
    final lookCtl = ref.read(appearanceProvider.notifier);
    final fonts = ref.watch(fontControllerProvider);
    final audio = ref.read(audioHandlerProvider);
    final library = ref.watch(libraryProvider);
    final tracks = ref.watch(tracksProvider).value ?? const [];
    final job = ref.watch(lyricsJobProvider);

    final withLyrics = tracks.where((t) => library.hasLyrics(t.id)).length;
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const TabHeader(title: 'Настройки'),
          const _Section('Тема'),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Тёмная'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Светлая'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Система'),
                ),
              ],
              selected: {theme.mode},
              onSelectionChanged: (v) => themeCtl.setMode(v.first),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Акцентный цвет',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),

          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              itemCount: kAccentChoices.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final color = kAccentChoices[i];
                final selected =
                    color.toARGB32() == theme.accent.toARGB32();

                return GestureDetector(
                  onTap: () => themeCtl.setAccent(color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.outline,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: color.computeLuminance() > 0.45
                                ? Colors.black
                                : Colors.white,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),

          ListTile(
            title: const Text('Свой цвет'),
            subtitle: Text(
              'Выберите любой оттенок акцента',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline),
              ),
            ),
            onTap: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (_) => _ColorDialog(
                  initial: theme.accent,
                ),
              );

              if (picked != null) {
                themeCtl.setAccent(picked);
              }
            },
          ),

          SpringSwitchTile(
            title: 'Чёрный AMOLED',
            subtitle: 'Чисто чёрный фон в тёмной теме',
            value: theme.amoled,
            onChanged: themeCtl.setAmoled,
          ),

          const _Section('Шрифт'),
          ListTile(
            title: const Text('Шрифт интерфейса'),
            subtitle: Text(ref.watch(fontControllerProvider).selectedName),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FontScreen()),
            ),
          ),

          const _Section('Оформление'),
          _ChoiceTile<int>(
            title: 'Толщина шрифта',
            hint: fonts.supportsWeight
                ? null
                : 'Меняется у встроенных шрифтов Manrope и Inter',
            enabled: fonts.supportsWeight,
            value: look.weightLevel,
            options: [
              for (var i = 0; i < BuiltInFont.weightLevels.length; i++)
                (i, BuiltInFont.weightLevels[i]),
            ],
            onChanged: lookCtl.setWeightLevel,
          ),
          _SliderTile(
            title: 'Размер текста',
            value: look.textScale,
            min: TextScaleRange.interfaceMin,
            max: TextScaleRange.interfaceMax,
            onChanged: lookCtl.setTextScale,
          ),
          _ChoiceTile<AnimationMode>(
            title: 'Анимации',
            hint: look.animation.description,
            value: look.animation,
            options: [for (final m in AnimationMode.values) (m, m.title)],
            onChanged: lookCtl.setAnimation,
          ),
          _ChoiceTile<EffectsLevel>(
            title: 'Визуальные эффекты',
            hint: 'Тени, цвет обложки на фоне плеера и экрана текстов',
            value: look.effects,
            options: [for (final e in EffectsLevel.values) (e, e.title)],
            onChanged: lookCtl.setEffects,
          ),
          _ChoiceTile<CoverShape>(
            title: 'Форма обложек',
            value: look.coverShape,
            options: [for (final c in CoverShape.values) (c, c.title)],
            onChanged: lookCtl.setCoverShape,
          ),
          _SliderTile(
            title: 'Размер текста песен',
            value: look.lyricsScale,
            min: TextScaleRange.lyricsMin,
            max: TextScaleRange.lyricsMax,
            onChanged: lookCtl.setLyricsScale,
          ),
          SpringSwitchTile(
            title: 'Строка текста под обложкой',
            subtitle: 'Текущая строка в плеере; нажатие открывает весь текст',
            value: look.showLyricPreview,
            onChanged: lookCtl.setShowLyricPreview,
          ),

          const _Section('Воспроизведение'),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Кроссфейд', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final seconds in const [0, 3, 6, 10, 12])
                      ChoiceChip(
                        label: Text(seconds == 0 ? 'Выкл' : '$seconds с'),
                        selected: settings.crossfadeSeconds == seconds,
                        onSelected: (_) {
                          audio.setCrossfade(Duration(seconds: seconds));
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Пропуск тишины'),
            subtitle: const Text('Убирает паузы в начале и конце треков (Android)'),
            trailing: SpringSwitch(
              value: settings.skipSilence,
              semanticLabel: 'Пропуск тишины',
              onChanged: (v) {
                audio.setSkipSilence(v);
                setState(() {});
              },
            ),
            onTap: () {
              audio.setSkipSilence(!settings.skipSilence);
              setState(() {});
            },
          ),

          const _Section('Тексты песен'),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<LyricsStyle>(
              showSelectedIcon: false,
              segments: [
                for (final style in LyricsStyle.values)
                  ButtonSegment(value: style, label: Text(style.title)),
              ],
              selected: {ref.watch(lyricsStyleProvider)},
              onSelectionChanged: (v) =>
                  ref.read(lyricsStyleProvider.notifier).set(v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              ref.watch(lyricsStyleProvider).description,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),

          SpringSwitchTile(
            title: 'Искать тексты автоматически',
            subtitle: 'После импорта подбирать тексты для новых треков '
                '(LRCLIB, Kugou, QQ Music, Lyrics.ovh)',
            value: settings.autoLyrics,
            onChanged: (v) => setState(() => settings.autoLyrics = v),
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: Text('Тексты: $withLyrics из ${tracks.length} треков'),
            subtitle: job.running
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: job.progress),
                        const SizedBox(height: 6),
                        Text(
                          'Ищу: ${job.done} из ${job.total} · найдено ${job.found}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    tracks.length == withLyrics
                        ? 'У всех треков есть текст'
                        : 'Можно найти тексты для остальных',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
            trailing: job.running
                ? TextButton(
                    onPressed: ref.read(lyricsJobProvider.notifier).cancel,
                    child: const Text('Стоп'),
                  )
                : TextButton(
                    onPressed: tracks.length == withLyrics
                        ? null
                        : ref.read(lyricsJobProvider.notifier).runMissing,
                    child: const Text('Найти'),
                  ),
          ),

          const _Section('Медиатека и хранилище'),

          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: Text('${tracks.length} треков'),
            subtitle: Text(
              totalDuration == Duration.zero
                  ? 'Импортируйте музыку на вкладке «Импорт»'
                  : 'Общая длительность: ${formatLongDuration(totalDuration)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),

          StorageMeter(
            data: _storageData,
            loading: _loadingCache,
            onRefresh: _loadCache,
          ),

          const _Section('История прослушивания'),

          ListTile(
            title: const Text('История прослушивания'),
            subtitle: Text(
              '${settings.recentIds.length} треков',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () {
                settings.clearHistory();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('История очищена')),
                );
              },
              child: const Text('Очистить'),
            ),
          ),

          const _Section('О приложении'),

          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(AppConfig.appName),
            subtitle: Text(
              'Версия ${AppConfig.appVersion} · локальный плеер без стриминга',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();

    return AlertDialog(
      title: const Text('Свой цвет'),
      content: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 9,
          ),
          activeTrackColor: color,
          thumbColor: color,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outline),
              ),
            ),
            const SizedBox(height: 12),
            _slider(
              'Оттенок',
              _hsv.hue,
              360,
              (v) => _hsv = _hsv.withHue(v),
            ),
            _slider(
              'Насыщенность',
              _hsv.saturation,
              1,
              (v) => _hsv = _hsv.withSaturation(v),
            ),
            _slider(
              'Яркость',
              _hsv.value,
              1,
              (v) => _hsv = _hsv.withValue(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double max,
    HSVColor Function(double) update,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: (v) {
              setState(() => update(v));
            },
          ),
        ),
      ],
    );
  }
}

/// Строка выбора из нескольких вариантов (чипы) с подписью.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final String title;
  final String? hint;
  final bool enabled;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (option, label) in options)
                ChoiceChip(
                  label: Text(label),
                  selected: option == value,
                  onSelected: enabled ? (_) => onChanged(option) : null,
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ползунок масштаба с подписью в процентах; шаг [TextScaleRange.step].
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final steps = ((max - min) / TextScaleRange.step).round();
    final percent = '${(value * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text(percent, style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: steps,
            label: percent,
            onChanged: (v) {
              final snapped = (v * 100).round() / 100;
              if (snapped != value) onChanged(snapped);
            },
          ),
        ],
      ),
    );
  }
}
