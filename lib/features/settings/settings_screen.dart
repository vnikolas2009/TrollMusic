import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/permission_service.dart';

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
    if (downloads.activeCount > 0) {
      downloads.cancelAll();
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Очистить скачанное?'),
        content: const Text(
          'Будут удалены аудиофайлы, обложки и тексты скачанных треков. '
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Section('Сеть'),
          _TextFieldTile(
            label: 'URL бэкенда (Vercel)',
            value: settings.apiBaseUrl,
            hint: AppConfig.defaultApiBase,
            onSaved: (v) => settings.apiBaseUrl = v,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Сервер отдаёт только метаданные Spotify (название, артист, '
              'длительность, обложка) и анонимный токен. Аудио идёт напрямую '
              'с SoundCloud / YouTube.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          SwitchListTile(
            title: const Text('Системный прокси'),
            subtitle: const Text('Использовать настройки ОС / переменные окружения'),
            value: settings.useSystemProxy,
            onChanged: (v) => setState(() => settings.useSystemProxy = v),
          ),
          _TextFieldTile(
            label: 'HTTP-прокси',
            value: settings.httpProxy,
            hint: 'http://user:pass@host:8080',
            onSaved: (v) => settings.httpProxy = v,
          ),
          _TextFieldTile(
            label: 'Дополнительные заголовки',
            value: settings.customHeaders,
            hint: 'User-Agent: ...\nX-Forwarded-For: ...',
            maxLines: 3,
            onSaved: (v) => setState(() => settings.customHeaders = v),
          ),
          const _Section('Spotify (без OAuth)'),
          SwitchListTile(
            title: const Text('Гостевой режим Spotify'),
            subtitle: const Text(
              'Анонимный токен и публичные метаданные: поиск работает '
              'без client id/secret',
            ),
            value: settings.spotifyGuestMode,
            onChanged: (v) => setState(() => settings.spotifyGuestMode = v),
          ),
          _TextFieldTile(
            label: 'Client ID',
            value: settings.spotifyClientId,
            hint: 'не обязательно: без ключей работает бэкенд и embed',
            onSaved: (v) => settings.spotifyClientId = v,
          ),
          _TextFieldTile(
            label: 'Client Secret',
            value: settings.spotifyClientSecret,
            hint: '••••••••',
            obscure: true,
            onSaved: (v) => settings.spotifyClientSecret = v,
          ),
          const _Section('Качество и воспроизведение'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Битрейт аудио', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final rate in AppConfig.audioBitrates)
                      ChoiceChip(
                        label: Text('$rate kbps'),
                        selected: settings.bitrate == rate,
                        onSelected: (_) => setState(() => settings.bitrate = rate),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Предпочитать Opus'),
            subtitle: const Text('Экономия трафика на мобильной сети'),
            value: settings.preferOpus,
            onChanged: (v) => setState(() => settings.preferOpus = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Кроссфейд', style: TextStyle(fontSize: 13)),
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
                          ref.read(audioHandlerProvider).setCrossfade(
                                Duration(seconds: seconds),
                              );
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const _Section('Кэш и офлайн'),
          ListTile(
            title: const Text('Занято на устройстве'),
            subtitle: Text(
              _loadingCache ? 'Подсчёт...' : formatBytes(_cacheBytes),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: _confirmClearCache,
              child: const Text('Очистить'),
            ),
          ),
          const _Section('История прослушивания'),
          ListTile(
            title: const Text('Очистить историю'),
            subtitle: Text(
              '${settings.recentIds.length} треков в истории',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () {
                ref.read(settingsProvider).clearHistory();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('История очищена')),
                );
              },
              child: const Text('Очистить'),
            ),
          ),
          const _Section('Разрешения'),
          ListTile(
            title: const Text('Уведомления'),
            subtitle: const Text('Экран блокировки и фоновое воспроизведение'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => PermissionService.requestNotifications(),
          ),
          ListTile(
            title: const Text('Доступ к аудиофайлам'),
            subtitle: const Text('Импорт локальных треков'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () => PermissionService.requestAudioFiles(),
          ),
          ListTile(
            title: const Text('Системные настройки'),
            subtitle: const Text('Открыть разрешения приложения'),
            trailing: const Icon(Icons.open_in_new, size: 16, color: AppColors.textSecondary),
            onTap: openAppSettings,
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
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _TextFieldTile extends StatefulWidget {
  const _TextFieldTile({
    required this.label,
    required this.value,
    required this.onSaved,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final ValueChanged<String> onSaved;

  @override
  State<_TextFieldTile> createState() => _TextFieldTileState();
}

class _TextFieldTileState extends State<_TextFieldTile> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextField(
        controller: _controller,
        obscureText: widget.obscure,
        maxLines: widget.obscure ? 1 : widget.maxLines,
        minLines: 1,
        onSubmitted: widget.onSaved,
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          widget.onSaved(_controller.text);
        },
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, size: 18),
            color: AppColors.accent,
            onPressed: () => widget.onSaved(_controller.text),
          ),
        ),
      ),
    );
  }
}
