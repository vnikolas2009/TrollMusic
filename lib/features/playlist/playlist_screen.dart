import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../services/download/download_service.dart';
import '../../shared/widgets/circle_collage.dart';
import '../../shared/widgets/track_tile.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({
    super.key,
    required this.id,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.isRadio = false,
    this.coverUrl,
  });

  final String id;
  final String title;
  final List<Track> tracks;
  final String? subtitle;
  final bool isRadio;
  final String? coverUrl;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  Color _dominant = const Color(0xFF3E3A1F);
  late List<Track> _tracks = [...widget.tracks];
  late String _title = widget.title;
  late String? _subtitle = widget.subtitle;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _resolveColor();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final playlist = ref.read(libraryProvider).playlistById(widget.id);
    if (playlist == null) return;
    if (!mounted) return;
    setState(() {
      _saved = true;
      _title = playlist.title;
      _subtitle = playlist.description.isEmpty ? null : playlist.description;
      _tracks = playlist.tracks;
    });
  }

  Future<void> _persist() async {
    final library = ref.read(libraryProvider);
    final existing = library.playlistById(widget.id);
    if (existing == null) return;
    await library.savePlaylist(
      existing.copyWith(
        title: _title,
        description: _subtitle ?? '',
        tracks: _tracks,
        colorValue: _dominant.value,
      ),
    );
  }

  Future<void> _addTracks() async {
    final library = ref.read(libraryProvider);
    final all = library.tracks;
    final existingIds = _tracks.map((t) => t.id).toSet();
    final candidates = all.where((t) => !existingIds.contains(t.id)).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В медиатеке нет новых треков')),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Добавить треки',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          sheetContext,
                          selected.isNotEmpty,
                        ),
                        child: Text('Готово (${selected.length})'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final track = candidates[i];
                      final checked = selected.contains(track.id);
                      return CheckboxListTile(
                        value: checked,
                        activeColor: AppColors.accent,
                        checkColor: Colors.black,
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            selected.add(track.id);
                          } else {
                            selected.remove(track.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || selected.isEmpty) return;
    final added = candidates.where((t) => selected.contains(t.id));
    setState(() => _tracks = [..._tracks, ...added]);
    if (!_saved) {
      await ref.read(libraryProvider).savePlaylist(
            Playlist(
              id: widget.id,
              title: _title,
              description: _subtitle ?? '',
              imageUrl: widget.coverUrl ?? _tracks.firstOrNull?.thumbnailUrl,
              tracks: _tracks,
              isRadio: widget.isRadio,
              colorValue: _dominant.value,
            ),
          );
      if (mounted) setState(() => _saved = true);
    } else {
      await _persist();
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Название плейлиста'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Новое название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    setState(() => _title = result);
    await _persist();
  }

  Future<void> _deletePlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Удалить плейлист?'),
        content: const Text('Треки останутся в медиатеке.'),
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
    await ref.read(libraryProvider).deletePlaylist(widget.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _removeTrack(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Убрать из плейлиста?'),
        content: Text(track.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _tracks = _tracks.where((t) => t.id != track.id).toList());
    await _persist();
  }

  Future<void> _resolveColor() async {
    final url = widget.coverUrl ?? _tracks.firstOrNull?.thumbnailUrl;
    if (url == null || url.isEmpty) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(96, 96),
      );
      final color = palette.darkMutedColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color;
      if (color != null && mounted) setState(() => _dominant = color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final audio = ref.read(audioHandlerProvider);
    final lead = tracks.firstOrNull;
    final total = tracks.fold(Duration.zero, (s, t) => s + t.duration);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 380,
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              PopupMenuButton<String>(
                color: AppColors.surfaceAlt,
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'add') _addTracks();
                  if (value == 'rename') _rename();
                  if (value == 'delete') _deletePlaylist();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'add', child: Text('Добавить треки')),
                  if (_saved)
                    const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  if (_saved)
                    const PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_dominant, AppColors.background],
                    stops: const [0, 0.85],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CircleCollage(
                          centerUrl: lead?.thumbnailUrl,
                          centerPath: lead?.artworkPath,
                          leftUrl: tracks.length > 1 ? tracks[1].thumbnailUrl : null,
                          rightUrl: tracks.length > 2 ? tracks[2].thumbnailUrl : null,
                          size: 150,
                          background: _dominant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _subtitle ??
                              '${widget.isRadio ? 'Радио' : 'Плейлист'} · '
                                  '${tracks.length} треков · ${formatLongDuration(total)}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RoundButton(
                              icon: Icons.shuffle_rounded,
                              onTap: () async {
                                await audio.setShuffle(true);
                                if (tracks.isNotEmpty) await audio.playTrack(tracks.first, contextQueue: tracks);
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: 46,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.textPrimary,
                                    foregroundColor: Colors.black,
                                    shape: const StadiumBorder(),
                                  ),
                                  onPressed: tracks.isEmpty
                                      ? null
                                      : () => audio.playTrack(tracks.first, contextQueue: tracks),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text(
                                    'Слушать',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _RoundButton(
                              icon: _saved ? Icons.edit_outlined : Icons.add,
                              onTap: () async {
                                final library = ref.read(libraryProvider);
                                final existing = library.playlistById(widget.id);
                                await library.savePlaylist(
                                  Playlist(
                                    id: widget.id,
                                    title: _title,
                                    description: _subtitle ?? '',
                                    imageUrl: widget.coverUrl ?? lead?.thumbnailUrl,
                                    tracks: _tracks,
                                    isRadio: widget.isRadio,
                                    colorValue: _dominant.value,
                                  ),
                                );
                                if (!mounted) return;
                                setState(() => _saved = true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(existing == null
                                        ? 'Добавлено в медиатеку'
                                        : 'Плейлист обновлён'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _RoundButton(
                              icon: Icons.download_rounded,
                              onTap: () async {
                                final downloads = ref.read(downloadProvider);
                                final pending = tracks
                                    .where((t) => !downloads.isDownloading(t.id))
                                    .where((t) =>
                                        t.localPath == null ||
                                        t.localPath!.isEmpty)
                                    .toList();
                                if (pending.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Все треки уже скачаны'),
                                    ),
                                  );
                                  return;
                                }
                                final messenger = ScaffoldMessenger.of(context);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Скачиваю 0 из ${pending.length}...',
                                    ),
                                  ),
                                );
                                await downloads.downloadAll(
                                  pending,
                                  onProgress: (done, total) {
                                    messenger
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Скачиваю $done из $total...',
                                          ),
                                        ),
                                      );
                                  },
                                );
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text('Скачивание завершено'),
                                    ),
                                  );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final track = tracks[i];
              final downloads = ref.read(downloadProvider);
              return ValueListenableBuilder<int>(
                valueListenable: downloads.revision,
                builder: (context, _, __) {
                  final progress = downloads.progressOf(track.id);
                  return TrackTile(
                    title: track.title,
                    artist: track.artist,
                    coverUrl: track.thumbnailUrl,
                    coverPath: track.artworkPath,
                    explicit: track.explicit,
                    downloaded: track.localPath != null && track.localPath!.isNotEmpty,
                    downloadProgress: progress?.fraction,
                    onTap: () => audio.playTrack(track, contextQueue: tracks),
                    onMenu: () => _showMenu(track, progress),
                  );
                },
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _showMenu(Track track, DownloadProgress? progress) {
    final downloads = ref.read(downloadProvider);
    final isDownloaded = track.localPath != null && track.localPath!.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                progress != null
                    ? Icons.stop_circle_outlined
                    : isDownloaded
                        ? Icons.delete_outline
                        : Icons.download_rounded,
              ),
              title: Text(
                progress != null
                    ? 'Отменить загрузку'
                    : isDownloaded
                        ? 'Удалить скачивание'
                        : 'Скачать трек',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (progress != null) {
                  downloads.cancel(track.id);
                  return;
                }
                try {
                  if (isDownloaded) {
                    await downloads.deleteDownload(track.id);
                  } else {
                    await downloads.download(track);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.lyrics_outlined),
              title: const Text('Найти текст (LRCLIB)'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await ref.read(importProvider).findLyricsOnline(track);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.found
                        ? (result.synced ? 'Найден синхронизированный текст' : 'Найден текст')
                        : 'Текст не найден'),
                  ),
                );
              },
            ),
            if (_saved)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Убрать из плейлиста'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeTrack(track);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
