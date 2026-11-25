import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';

/// Плейлист: воспроизведение, добавление, порядок, переименование, удаление.
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool _reordering = false;

  Playlist? get _playlist => ref.read(libraryProvider).playlistById(widget.id);

  Future<void> _save(Playlist playlist) =>
      ref.read(libraryProvider).savePlaylist(playlist);

  /// Актуальные данные треков из медиатеки (теги и обложки могли измениться);
  /// удалённые с устройства треки отбрасываются.
  List<Track> _fresh(Playlist playlist) {
    final library = ref.read(libraryProvider);
    return [
      for (final t in playlist.tracks)
        if (library.trackById(t.id) != null) library.trackById(t.id)!,
    ];
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await askText(
      context,
      title: 'Название плейлиста',
      initial: playlist.title,
    );
    if (name == null || name.isEmpty) return;
    await _save(playlist.copyWith(title: name));
  }

  Future<void> _delete(Playlist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить плейлист?'),
        content: Text('«${playlist.title}» будет удалён. Треки останутся в медиатеке.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(libraryProvider).deletePlaylist(widget.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addTracks(Playlist playlist) async {
    final have = playlist.tracks.map((t) => t.id).toSet();
    final candidates = ref
        .read(libraryProvider)
        .tracks
        .where((t) => !have.contains(t.id))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Добавить треки',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheet, selected.isNotEmpty),
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
                      return CheckboxListTile(
                        value: selected.contains(track.id),
                        activeColor: AppColors.accent,
                        checkColor: Colors.black,
                        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        onChanged: (v) => setSheet(() {
                          v == true ? selected.add(track.id) : selected.remove(track.id);
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
    await _save(playlist.copyWith(tracks: [...playlist.tracks, ...added]));
  }

  Future<void> _removeAt(Playlist playlist, int index) async {
    final tracks = [...playlist.tracks]..removeAt(index);
    await _save(playlist.copyWith(tracks: tracks));
  }

  Future<void> _move(Playlist playlist, int oldIndex, int newIndex) async {
    final tracks = [...playlist.tracks];
    if (newIndex > oldIndex) newIndex -= 1;
    tracks.insert(newIndex, tracks.removeAt(oldIndex));
    await _save(playlist.copyWith(tracks: tracks));
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовка при любом изменении плейлистов и медиатеки.
    ref.watch(playlistsProvider);
    ref.watch(tracksProvider);
    final library = ref.watch(libraryProvider);
    final current = ref.watch(currentTrackProvider).value;
    final audio = ref.read(audioHandlerProvider);

    final playlist = _playlist;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Плейлист удалён')),
      );
    }
    final tracks = _fresh(playlist);
    final total = tracks.fold<Duration>(Duration.zero, (s, t) => s + t.duration);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.appBarBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Добавить треки',
            onPressed: () => _addTracks(playlist),
            icon: const Icon(Icons.add_rounded),
          ),
          PopupMenuButton<String>(
            color: AppColors.surfaceAlt,
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _rename(playlist);
                case 'order':
                  setState(() => _reordering = !_reordering);
                case 'delete':
                  _delete(playlist);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
              PopupMenuItem(
                value: 'order',
                child: Text(_reordering ? 'Готово' : 'Изменить порядок'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Удалить плейлист')),
            ],
          ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('В плейлисте пока нет треков'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _addTracks(playlist),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить треки'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      CoverMosaic(
                        paths: tracks.map((t) => t.artworkPath).toList(),
                        size: 96,
                        radius: 16,
                        icon: Icons.queue_music_rounded,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tracks.length} треков · ${formatLongDuration(total)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () => audio.setLibraryQueue(tracks),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Играть'),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip: 'Вперемешку',
                                  onPressed: () => audio.playShuffled(tracks),
                                  icon: const Icon(Icons.shuffle_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _reordering
                      ? ReorderableListView.builder(
                          itemCount: playlist.tracks.length,
                          onReorder: (a, b) => _move(playlist, a, b),
                          itemBuilder: (context, i) {
                            final t = playlist.tracks[i];
                            return ListTile(
                              key: ValueKey('${t.id}#$i'),
                              leading: CoverArt(path: t.artworkPath, size: 44, radius: 8),
                              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.drag_handle_rounded),
                            );
                          },
                        )
                      : ListView.builder(
                          itemCount: tracks.length + 1,
                          itemBuilder: (context, i) {
                            if (i == tracks.length) return const SizedBox(height: 96);
                            final track = tracks[i];
                            return TrackTile(
                              title: track.title,
                              artist: track.artist,
                              coverPath: track.artworkPath,
                              active: current?.id == track.id,
                              hasLyrics: library.hasLyrics(track.id),
                              onTap: () => audio.playTrack(track, contextQueue: tracks),
                              onMenu: () => showTrackActions(
                                context,
                                ref,
                                track,
                                removeLabel: 'Убрать из плейлиста',
                                onRemove: () => _removeAt(playlist, i),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
