import 'dart:io';

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
  int _revision = 0;

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
          _ArtworkPreview(track: _track, revision: _revision),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(importProvider).importArtworkFromFile(widget.trackId);
                  setState(() => _revision++);
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('Выбрать изображение'),
              ),
              if (_track?.artworkPath != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final track = _track;
                    if (track == null) return;
                    final library = ref.read(libraryProvider);
                    await library.saveTrack(track.copyWith(artworkPath: ''));
                    setState(() => _revision++);
                  },
                  icon: const Icon(Icons.image_not_supported_outlined),
                  label: const Text('Сбросить'),
                ),
            ],
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
          _LyricsStatus(trackId: widget.trackId, revision: _revision),
          if (ref.watch(libraryProvider).hasLyrics(widget.trackId)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showCurrentLyrics(),
              icon: const Icon(Icons.notes),
              label: const Text('Посмотреть текст'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.surfaceAlt,
                    title: const Text('Удалить текст песни?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await ref.read(libraryProvider).clearLyrics(widget.trackId);
                setState(() => _revision++);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Удалить текст'),
            ),
          ],
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

  void _showCurrentLyrics() {
    final raw = ref.read(libraryProvider).lyricsFor(widget.trackId) ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.7,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Текст песни', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Text(
                    raw.isEmpty ? 'Текст не задан' : raw,
                    style: const TextStyle(fontSize: 13, height: 1.7),
                  ),
                ),
              ),
            ],
          ),
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

class _ArtworkPreview extends StatelessWidget {
  const _ArtworkPreview({required this.track, required this.revision});

  final Track? track;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final path = track?.artworkPath;
    final url = track?.thumbnailUrl;

    final child = path != null && path.isNotEmpty
        ? Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
        : url != null && url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder();

    return Row(
      key: ValueKey(revision),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 72, height: 72, child: child),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            path != null && path.isNotEmpty
                ? 'Своя обложка'
                : 'Используется обложка из источника',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceHigh,
        child: const Icon(Icons.music_note, color: AppColors.textSecondary),
      );
}

class _LyricsStatus extends ConsumerWidget {
  const _LyricsStatus({required this.trackId, required this.revision});

  final String trackId;
  final int revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final has = library.hasLyrics(trackId);
    final raw = library.lyricsFor(trackId) ?? '';
    final synced = raw.contains(RegExp(r'\[\d{1,3}:\d{1,2}'));

    return Row(
      key: ValueKey('status-$revision'),
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
