import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../app/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/audio_pick.dart';
import '../../core/utils/formatters.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _cacheBytes = 0;
  bool _loadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadCache();
  }

  Future<void> _loadCache() async {
    final bytes = await ref.read(storageProvider).usedBytes();
    if (!mounted) return;
    setState(() {
      _cacheBytes = bytes;
      _loadingCache = false;
    });
  }

  Future<void> _confirmClearCache() async {
    final downloads = ref.read(downloadProvider);
    if (downloads.activeCount > 0) downloads.cancelAll();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить кэш?'),
        content: const Text(
          'Будут удалены скачанные аудиофайлы, обложки и тексты. '
          'Импортированные локальные файлы останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(storageProvider).clearCache();
    await _loadCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Кэш очищен')));
  }

  static const _qualityLabels = {
    AudioQuality.low: 'Низкое',
    AudioQuality.medium: 'Среднее',
    AudioQuality.high: 'Высокое',
    AudioQuality.auto: 'Авто',
  };

  static const _qualityHints = {
    AudioQuality.low: '≈ 64 кбит/с — минимум трафика',
    AudioQuality.medium: '≈ 128 кбит/с — баланс',
    AudioQuality.high: 'Максимум, что отдаёт источник',
    AudioQuality.auto: 'Высокое по Wi‑Fi, среднее по мобильной сети',
  };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = ref.watch(themeControllerProvider);
    final themeCtl = ref.read(themeControllerProvider.notifier);
    final audio = ref.read(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Section('Качество звука'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in AudioQuality.values)
                      ChoiceChip(
                        label: Text(_qualityLabels[q]!),
                        selected: settings.audioQuality == q,
                        onSelected: (_) =>
                            setState(() => settings.audioQuality = q),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _qualityHints[settings.audioQuality]!,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const _Section('Тема'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.system, label: Text('Система')),
              ],
              selected: {theme.mode},
              onSelectionChanged: (v) => themeCtl.setMode(v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Акцентный цвет',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: kAccentChoices.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final color = kAccentChoices[i];
                final selected = color.toARGB32() == theme.accent.toARGB32();
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
          SwitchListTile(
            title: const Text('Градиентный фон'),
            subtitle: const Text('Едва заметный градиент от акцентного цвета'),
            value: theme.gradient,
            onChanged: themeCtl.setGradient,
          ),
          SwitchListTile(
            title: const Text('Чёрный AMOLED'),
            subtitle: const Text('Чисто чёрный фон в тёмной теме'),
            value: theme.amoled,
            onChanged: themeCtl.setAmoled,
          ),
          const _Section('Воспроизведение'),
          SwitchListTile(
            title: const Text('Без пауз (gapless)'),
            subtitle: const Text('Следующий трек подготавливается заранее'),
            value: settings.gaplessEnabled,
            onChanged: (v) => setState(() => settings.gaplessEnabled = v),
          ),
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
                          settings.crossfadeSeconds = seconds;
                          audio.setCrossfade(Duration(seconds: seconds));
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Нормализация громкости'),
            subtitle: const Text('Выравнивает громкость разных треков'),
            value: settings.normalizeVolume,
            onChanged: (v) {
              settings.normalizeVolume = v;
              audio.refreshNormalization();
              setState(() {});
            },
          ),
          const _Section('Кэш и хранилище'),
          ListTile(
            title: const Text('Занято на устройстве'),
            subtitle: Text(
              _loadingCache ? 'Подсчёт...' : formatBytes(_cacheBytes),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: _confirmClearCache,
              child: const Text('Очистить кэш'),
            ),
          ),
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
