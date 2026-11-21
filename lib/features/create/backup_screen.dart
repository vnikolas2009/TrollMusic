import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = ref.read(libraryProvider).exportJson();
      final encoded = const JsonEncoder.withIndent('  ').convert(data);
      await FilePicker.saveFile(
        fileName: 'trollmusic-backup.json',
        bytes: Uint8List.fromList(utf8.encode(encoded)),
        mimeType: 'application/json',
        dialogTitle: 'Сохранить резервную копию',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Резервная копия сохранена')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Выбрать резервную копию',
    );
    final path = picked?.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final raw = await File(path).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      await ref.read(libraryProvider).importJson(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Медиатека импортирована')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyJson() async {
    final data = ref.read(libraryProvider).exportJson();
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Скопировано: ${encoded.length} символов')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final tracks = ref.watch(tracksProvider).value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Резервная копия')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Треков: ${tracks.length} · Плейлистов: ${playlists.length}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.textPrimary,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(46),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Экспорт в JSON'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.surfaceHigh),
              minimumSize: const Size.fromHeight(46),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Импорт из JSON'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.surfaceHigh),
              minimumSize: const Size.fromHeight(46),
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _copyJson,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Скопировать JSON в буфер'),
          ),
          const SizedBox(height: 24),
          Text(
            'Копия содержит треки, плейлисты и тексты песен. '
            'Аудиофайлы и обложки нужно переносить отдельно.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}
