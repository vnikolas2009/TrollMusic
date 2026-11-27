import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/track_filter.dart';
import '../../core/utils/track_groups.dart';
import '../../core/utils/track_search.dart';
import '../../core/utils/track_sort.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/tab_header.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';
import '../playlist/playlist_screen.dart';
import 'track_list_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  static const _labels = [
    'Все треки',
    'Плейлисты',
    'Исполнители',
    'Альбомы',
    'Избранное',
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _newPlaylist() async {
    final name = await askText(context, title: 'Новый плейлист', hint: 'Название');
    if (name == null || name.isEmpty) return;
    final id = 'user:${DateTime.now().millisecondsSinceEpoch}';
    await ref.read(libraryProvider).savePlaylist(Playlist(id: id, title: name));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlaylistScreen(id: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tracksProvider).value ?? const <Track>[];
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final liked = ref.watch(likedProvider).value ?? const <Track>[];

    return Column(
      children: [
        TabHeader(
          title: 'Медиатека',
          trailing: IconButton(
            tooltip: 'Новый плейлист',
            onPressed: _newPlaylist,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          indicatorColor: AppColors.textPrimary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _labels.map((l) => Tab(text: l)).toList(),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _AllTracksTab(tracks: all),
              _PlaylistsTab(playlists: playlists, onCreate: _newPlaylist),
              _GroupsTab(
                groups: groupTracksByArtist(all),
                icon: Icons.person_rounded,
                circle: true,
                open: (name) => TrackListScreen.artist(name: name),
                emptyText: 'Исполнители появятся после импорта музыки.',
              ),
              _GroupsTab(
                groups: groupTracksByAlbum(all),
                icon: Icons.album_rounded,
                open: (name) => TrackListScreen.album(name: name),
                emptyText: 'Нет альбомов: в тегах файлов не указан альбом.',
              ),
              _TracksList(
                tracks: liked,
                emptyText: 'Нет избранных треков.\nОтметьте сердечком в плеере или меню трека.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ),
      );
}

class _TracksList extends ConsumerWidget {
  const _TracksList({required this.tracks, required this.emptyText});

  final List<Track> tracks;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return _Empty(emptyText);
    final library = ref.watch(libraryProvider);
    final current = ref.watch(currentTrackProvider).value;
    final audio = ref.read(audioHandlerProvider);

    return ListView.builder(
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
          subtitleExtra:
              track.duration == Duration.zero ? null : formatDuration(track.duration),
          onTap: () => audio.playTrack(track, contextQueue: tracks),
          onMenu: () => showTrackActions(context, ref, track),
        );
      },
    );
  }
}

class _AllTracksTab extends ConsumerStatefulWidget {
  const _AllTracksTab({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_AllTracksTab> createState() => _AllTracksTabState();
}

class _AllTracksTabState extends ConsumerState<_AllTracksTab> {
  final _controller = TextEditingController();
  String _query = '';
  late TrackSort _sort = TrackSort.fromIndex(ref.read(settingsProvider).sortIndex);
  bool _onlyWithoutLyrics = false;
  bool _onlyWithoutArtwork = false;

  /// Быстрое добавление обложек: по очереди предлагает выбрать картинку для
  /// каждого трека из списка, можно пропустить трек или остановиться.
  Future<void> _addCovers(List<Track> list) async {
    final queue = [...list];
    var added = 0;

    for (var i = 0; i < queue.length; i++) {
      if (!mounted) return;
      final track = queue[i];
      final action = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: Text('Обложка ${i + 1} из ${queue.length}'),
          content: Text('«${track.title}» — ${track.artist}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, 'stop'), child: const Text('Стоп')),
            TextButton(onPressed: () => Navigator.pop(dialog, 'skip'), child: const Text('Пропустить')),
            FilledButton(onPressed: () => Navigator.pop(dialog, 'pick'), child: const Text('Выбрать')),
          ],
        ),
      );
      if (action == null || action == 'stop') break;
      if (action == 'skip') continue;

      try {
        final updated = await ref.read(importProvider).importArtworkFromFile(track.id);
        if (updated != null) added++;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не удалось добавить обложку: $e')));
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено обложек: $added')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final library = ref.watch(libraryProvider);
    final audio = ref.read(audioHandlerProvider);

    var tracks = sortTracks(
      filterTracks(widget.tracks, _query),
      _sort,
      playCounts: settings.playCounts,
    );
    if (_onlyWithoutLyrics) {
      tracks = tracks.where((t) => !library.hasLyrics(t.id)).toList();
    }
    if (_onlyWithoutArtwork) {
      tracks = tracks.where(lacksArtwork).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Поиск по медиатеке',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<Object>(
                tooltip: 'Сортировка',
                color: AppColors.surfaceAlt,
                icon: const Icon(Icons.sort_rounded),
                onSelected: (value) {
                  setState(() {
                    if (value is TrackSort) {
                      _sort = value;
                      settings.sortIndex = value.index;
                    } else if (value == 'artwork') {
                      _onlyWithoutArtwork = !_onlyWithoutArtwork;
                    } else {
                      _onlyWithoutLyrics = !_onlyWithoutLyrics;
                    }
                  });
                },
                itemBuilder: (_) => [
                  for (final sort in TrackSort.values)
                    CheckedPopupMenuItem<Object>(
                      value: sort,
                      checked: sort == _sort,
                      child: Text(sort.label),
                    ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem<Object>(
                    value: 'lyrics',
                    checked: _onlyWithoutLyrics,
                    child: const Text('Только без текста'),
                  ),
                  CheckedPopupMenuItem<Object>(
                    value: 'artwork',
                    checked: _onlyWithoutArtwork,
                    child: const Text('Только без обложек'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_onlyWithoutArtwork && tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: FilledButton.tonalIcon(
              onPressed: () => _addCovers(tracks),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text('Добавить обложки по очереди (${tracks.length})'),
            ),
          ),
        if (tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${tracks.length} треков',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => audio.playShuffled(tracks),
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Вперемешку'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _TracksList(
            tracks: tracks,
            emptyText: widget.tracks.isEmpty
                ? 'Медиатека пуста.\nИмпортируйте музыку на вкладке «Импорт».'
                : 'Ничего не найдено.',
          ),
        ),
      ],
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.playlists, required this.onCreate});

  final List<Playlist> playlists;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Плейлистов пока нет'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать плейлист'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: playlists.length + 1,
      itemBuilder: (context, i) {
        if (i == playlists.length) return const SizedBox(height: 96);
        final playlist = playlists[i];
        return _GroupRow(
          title: playlist.title,
          subtitle:
              '${playlist.tracks.length} треков · ${formatLongDuration(playlist.totalDuration)}',
          paths: playlist.tracks.map((t) => t.artworkPath).toList(),
          icon: Icons.queue_music_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PlaylistScreen(id: playlist.id)),
          ),
        );
      },
    );
  }
}

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({
    required this.groups,
    required this.icon,
    required this.open,
    required this.emptyText,
    this.circle = false,
  });

  final Map<String, List<Track>> groups;
  final IconData icon;
  final bool circle;
  final Widget Function(String name) open;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return _Empty(emptyText);
    final names = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ListView.builder(
      itemCount: names.length + 1,
      itemBuilder: (context, i) {
        if (i == names.length) return const SizedBox(height: 96);
        final name = names[i];
        final tracks = groups[name]!;
        return _GroupRow(
          title: name,
          subtitle: '${tracks.length} треков',
          paths: tracks.map((t) => t.artworkPath).toList(),
          icon: icon,
          circle: circle,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => open(name)),
          ),
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.title,
    required this.subtitle,
    required this.paths,
    required this.icon,
    required this.onTap,
    this.circle = false,
  });

  final String title;
  final String subtitle;
  final List<String?> paths;
  final IconData icon;
  final bool circle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final firstCover = paths.whereType<String>().firstWhere(
          (p) => p.isNotEmpty,
          orElse: () => '',
        );
    return PressScale(
      scale: 0.98,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            circle
                ? CoverArt(
                    path: firstCover.isEmpty ? null : firstCover,
                    size: 56,
                    circle: true,
                    placeholderIcon: icon,
                  )
                : CoverMosaic(paths: paths, size: 56, radius: 12, icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
