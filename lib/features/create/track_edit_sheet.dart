import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/track.dart';

class TrackEditSheet extends ConsumerStatefulWidget {
  const TrackEditSheet({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<TrackEditSheet> createState() => _TrackEditSheetState();
}

class _TrackEditSheetState extends ConsumerState<TrackEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  String _lyricsInput = '';

  @override
  void initState() {
    super.initState();
    final track = ref.read(libraryProvider).trackById(widget.trackId);
    _title = TextEditingController(text: track?.title ?? '');
    _artist = TextEditingController(text: track?.artist ?? '');
    _album = TextEditingController(text: track?.album ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Track? get _track => ref.read(libraryProvider).trackById(widget.trackId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Редактировать трек'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(importProvider).updateTags(
                    widget.trackId,
                    title: _title.text.trim(),
                    artist: _artist.text.trim(),
                    album: _album.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Готово'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Название', _title),
          const SizedBox(height: 12),
          _field('Исполнитель', _artist),
          const SizedBox(height: 12),
          _field('Альбом', _album),
          const SizedBox(height: 24),
          const Text('Обложка', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(importProvider).importArtworkFromFile(widget.trackId);
              setState(() {});
            },
            icon: const Icon(Icons.image_outlined),
            label: const Text('Выбрать изображение'),
          ),
          const SizedBox(height: 24),
          const Text('Текст песни', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final track = _track;
                  if (track == null) return;
                  final result = await ref.read(importProvider).findLyricsOnline(track);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.found
                          ? (result.synced ? 'Найден LRC с таймкодами' : 'Найден текст без таймкодов')
                          : 'Текст не найден в LRCLIB'),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
                label: const Text('Найти в LRCLIB'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(importProvider).importLyricsFromFile(widget.trackId);
                  setState(() {});
                },
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Загрузить .lrc'),
              ),
              OutlinedButton.icon(
                onPressed: _openManualLyrics,
                icon: const Icon(Icons.edit_note),
                label: const Text('Вставить текст'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LyricsStatus(trackId: widget.trackId),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _openManualLyrics() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Вставьте LRC или текст', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              maxLines: 10,
              onChanged: (v) => _lyricsInput = v,
              style: const TextStyle(fontSize: 12, height: 1.5),
              decoration: const InputDecoration(
                hintText: '[00:12.30] Первая строка\n[00:18.10] Вторая строка',
                filled: true,
                fillColor: AppColors.surfaceHigh,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: () async {
                  if (_lyricsInput.trim().isEmpty) return;
                  await ref.read(importProvider).saveManualLyrics(widget.trackId, _lyricsInput);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  setState(() {});
                },
                child: const Text('Сохранить'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _LyricsStatus extends ConsumerWidget {
  const _LyricsStatus({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final has = library.hasLyrics(trackId);
    final raw = library.lyricsFor(trackId) ?? '';
    final synced = raw.contains(RegExp(r'\[\d{1,3}:\d{1,2}'));

    return Row(
      children: [
        Icon(
          has ? Icons.check_circle : Icons.info_outline,
          size: 16,
          color: has ? AppColors.accent : AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Text(
          has
              ? (synced ? 'Текст с таймкодами сохранён' : 'Текст сохранён (без таймкодов)')
              : 'Текст не задан',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
