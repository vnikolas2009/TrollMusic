import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../app/source_provider.dart';
import '../../app/theme_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/audio_pick.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/spring_switch.dart';
import 'network_diagnostics_screen.dart';

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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.appBarBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Настройки'),
      ),
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
          ListTile(
            title: const Text('Свой цвет'),
            subtitle: Text(
              'Выберите любой оттенок акцента',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                builder: (_) => _ColorDialog(initial: theme.accent),
              );
              if (picked != null) themeCtl.setAccent(picked);
            },
          ),
          ListTile(
            title: const Text('Градиентный фон'),
            subtitle: const Text('Едва заметный градиент от акцентного цвета'),
            trailing: SpringSwitch(
              value: theme.gradient,
              semanticLabel: 'Градиентный фон',
              onChanged: themeCtl.setGradient,
            ),
            onTap: () {
              final next = !(theme.gradient);
              (themeCtl.setGradient)(next);
            },
          ),
          ListTile(
            title: const Text('Чёрный AMOLED'),
            subtitle: const Text('Чисто чёрный фон в тёмной теме'),
            trailing: SpringSwitch(
              value: theme.amoled,
              semanticLabel: 'Чёрный AMOLED',
              onChanged: themeCtl.setAmoled,
            ),
            onTap: () {
              final next = !(theme.amoled);
              (themeCtl.setAmoled)(next);
            },
          ),
          const _Section('Воспроизведение'),
          ListTile(
            title: const Text('Без пауз (gapless)'),
            subtitle: const Text('Следующий трек подготавливается заранее'),
            trailing: SpringSwitch(
              value: settings.gaplessEnabled,
              semanticLabel: 'Без пауз (gapless)',
              onChanged: (v) => setState(() => settings.gaplessEnabled = v),
            ),
            onTap: () {
              final next = !(settings.gaplessEnabled);
              ((v) => setState(() => settings.gaplessEnabled = v))(next);
            },
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
          const _Section('Сеть'),
          ListTile(
            leading: const Icon(Icons.network_check_rounded),
            title: const Text('Диагностика сети'),
            subtitle: const Text('Какие серверы доступны с вашего интернета'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NetworkDiagnosticsScreen(),
              ),
            ),
          ),
          const _Section('Источники музыки'),
          _TokenField(
            label: 'Яндекс Музыка · OAuth-токен',
            help: 'Необязательно. Поиск и чарты работают без токена; с токеном '
                'треки играют напрямую из Яндекс Музыки (нужна ваша подписка). '
                'Токен хранится только на этом устройстве и отправляется '
                'только в Яндекс.',
            initial: ref.read(serviceTokensProvider).yandex,
            onSave: ref.read(serviceTokensProvider.notifier).setYandex,
          ),
          _TokenField(
            label: 'VK Музыка · токен',
            help: 'Нужен для VK Музыки. VK разрешает методы музыки не всем '
                'токенам, поэтому доступ не гарантирован. Токен хранится '
                'только на этом устройстве и отправляется только в VK.',
            initial: ref.read(serviceTokensProvider).vk,
            onSave: ref.read(serviceTokensProvider.notifier).setVk,
          ),
          ListTile(
            leading: const Icon(Icons.public_rounded),
            title: const Text('Audius'),
            subtitle: Text(
              'Открытый каталог независимых артистов — токен не нужен',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
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

/// Поле личного токена: скрыто по умолчанию, сохраняется кнопкой или Enter.
class _TokenField extends StatefulWidget {
  const _TokenField({
    required this.label,
    required this.help,
    required this.initial,
    required this.onSave,
  });

  final String label;
  final String help;
  final String initial;
  final ValueChanged<String> onSave;

  @override
  State<_TokenField> createState() => _TokenFieldState();
}

class _TokenFieldState extends State<_TokenField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save([String? _]) {
    final value = _controller.text.trim();
    widget.onSave(value);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.isEmpty ? 'Токен удалён' : 'Токен сохранён')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: _save,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_rounded, size: 22),
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.help,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
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

/// Простой выбор цвета: оттенок, насыщенность и яркость.
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
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
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
          _slider('Оттенок', _hsv.hue, 360, (v) => _hsv = _hsv.withHue(v)),
          _slider('Насыщенность', _hsv.saturation, 1,
              (v) => _hsv = _hsv.withSaturation(v)),
          _slider('Яркость', _hsv.value, 1, (v) => _hsv = _hsv.withValue(v)),
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
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: (v) => setState(() => update(v)),
          ),
        ),
      ],
    );
  }
}
