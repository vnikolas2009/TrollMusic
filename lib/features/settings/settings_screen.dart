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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Section('Сеть и прокси'),
          _TextFieldTile(
            label: 'Cloudflare Worker URL',
            value: settings.workerUrl,
            hint: AppConfig.defaultWorkerUrl,
            onSaved: (v) {
              settings.workerUrl = v;
              ref.read(mirrorManagerProvider).resetHealth();
            },
          ),
          SwitchListTile(
            title: const Text('Проксировать через Worker'),
            subtitle: const Text('Spotify API, обложки, аудиопоток Piped'),
            value: settings.useWorkerProxy,
            activeThumbColor: AppColors.accent,
            onChanged: (v) => setState(() => settings.useWorkerProxy = v),
          ),
          _Section('Spotify (опционально)'),
          _TextFieldTile(
            label: 'Client ID',
            value: settings.spotifyClientId,
            hint: 'без ключей — парсинг эмбедов',
            onSaved: (v) => settings.spotifyClientId = v,
          ),
          _TextFieldTile(
            label: 'Client Secret',
            value: settings.spotifyClientSecret,
            hint: '••••••••',
            obscure: true,
            onSaved: (v) => settings.spotifyClientSecret = v,
          ),
          _Section('Зеркала YouTube (Piped / Invidious)'),
          for (var i = 0; i < settings.pipedInstances.length; i++)
            _MirrorTile(
              origin: settings.pipedInstances[i],
              onDelete: () {
                final list = [...settings.pipedInstances]..removeAt(i);
                setState(() => settings.pipedInstances = list);
                ref.read(mirrorManagerProvider).resetHealth();
              },
            ),
          _AddMirrorButton(
            label: 'Добавить Piped-инстанс',
            onAdd: (value) {
              setState(() => settings.pipedInstances = [...settings.pipedInstances, value]);
              ref.read(mirrorManagerProvider).resetHealth();
            },
          ),
          for (var i = 0; i < settings.invidiousInstances.length; i++)
            _MirrorTile(
              origin: settings.invidiousInstances[i],
              onDelete: () {
                final list = [...settings.invidiousInstances]..removeAt(i);
                setState(() => settings.invidiousInstances = list);
                ref.read(mirrorManagerProvider).resetHealth();
              },
            ),
          _AddMirrorButton(
            label: 'Добавить Invidious-инстанс',
            onAdd: (value) {
              setState(() => settings.invidiousInstances = [...settings.invidiousInstances, value]);
              ref.read(mirrorManagerProvider).resetHealth();
            },
          ),
          _Section('Качество и воспроизведение'),
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
                        selectedColor: AppColors.textPrimary,
                        labelStyle: TextStyle(
                          color: settings.bitrate == rate ? Colors.black : AppColors.textPrimary,
                          fontSize: 12,
                        ),
                        backgroundColor: AppColors.surfaceAlt,
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
            activeThumbColor: AppColors.accent,
            onChanged: (v) => setState(() => settings.preferOpus = v),
          ),
          SwitchListTile(
            title: const Text('Проксировать аудиопоток'),
            subtitle: const Text('Обход блокировок googlevideo.com'),
            value: settings.proxyAudioStreams,
            activeThumbColor: AppColors.accent,
            onChanged: (v) => setState(() => settings.proxyAudioStreams = v),
          ),
          _Section('Кэш и офлайн'),
          ListTile(
            title: const Text('Занято на устройстве'),
            subtitle: Text(
              _loadingCache ? 'Подсчёт...' : formatBytes(_cacheBytes),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () async {
                await ref.read(storageProvider).clearCache();
                await _loadCache();
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Кэш очищен')));
              },
              child: const Text('Очистить'),
            ),
          ),
          _Section('Разрешения'),
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: AppColors.textSecondary,
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
  });

  final String label;
  final String value;
  final String? hint;
  final bool obscure;
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

class _MirrorTile extends StatelessWidget {
  const _MirrorTile({required this.origin, required this.onDelete});

  final String origin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(origin, style: const TextStyle(fontSize: 12)),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        color: AppColors.textSecondary,
        onPressed: onDelete,
      ),
    );
  }
}

class _AddMirrorButton extends StatelessWidget {
  const _AddMirrorButton({required this.label, required this.onAdd});

  final String label;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.surfaceHigh),
          minimumSize: const Size.fromHeight(40),
        ),
        onPressed: () async {
          final controller = TextEditingController();
          final value = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: AppColors.surfaceAlt,
              title: Text(label),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'https://api.example.com'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, controller.text),
                  child: const Text('Добавить'),
                ),
              ],
            ),
          );
          final trimmed = value?.trim();
          if (trimmed != null && trimmed.startsWith('http')) onAdd(trimmed);
          controller.dispose();
        },
        icon: const Icon(Icons.add, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
