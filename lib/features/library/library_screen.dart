import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/track_search.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../services/download/download_service.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/track_tile.dart';
import '../create/track_edit_sheet.dart';
import '../playlist/playlist_screen.dart';

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
    'Скачанные',
    'Локальные',
    'Избранное',
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tracksProvider).value ?? const <Track>[];
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final downloaded = ref.watch(downloadedProvider).value ?? const <Track>[];
    final local = ref.watch(localTracksProvider).value ?? const <Track>[];
    final liked = ref.watch(likedProvider).value ?? const <Track>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Медиатека',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    height: 1.1,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Новый плейлист',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(
                      id: 'user:${DateTime.now().millisecondsSinceEpoch}',
                      title: 'Новый плейлист',
                      tracks: const [],
                    ),
                  ),
                ),
                icon: const Icon(Icons.playlist_add_rounded),
              ),
            ],
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
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _labels.map((l) => Tab(text: l)).toList(),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _AllTracksTab(tracks: all),
              _PlaylistsTab(playlists: playlists),
              _DownloadedTab(tracks: downloaded),
              _TracksTab(
                tracks: local,
                emptyText: 'Нет локальных треков.\nИмпортируйте во вкладке «Создать».',
              ),
              _TracksTab(
                tracks: liked,
                emptyText: 'Нет избранных треков.',
              ),
            ],
          ),
        ),
      ],
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Медиатека пуста.\nНайдите музыку в «Поиске» или импортируйте файлы.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    final tracks = filterTracks(widget.tracks, _query).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: TextField(
            controller: _controller,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Поиск по медиатеке',
              hintStyle: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tracks.isEmpty
                      ? 'Ничего не найдено'
                      : '${tracks.length} треков · ${formatLongDuration(totalDuration)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              if (tracks.isNotEmpty)
                IconButton(
                  tooltip: 'Слушать всё',
                  onPressed: () => ref
                      .read(audioHandlerProvider)
                      .playTrack(tracks.first, contextQueue: tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
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
                    downloaded:
                        track.localPath != null && track.localPath!.isNotEmpty,
                    downloadProgress: progress?.fraction,
                    index: i,
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTrack(track, contextQueue: tracks),
                    onMenu: () =>
                        _trackMenu(context, ref, track, progress, downloads),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _trackMenu(
    BuildContext context,
    WidgetRef ref,
    Track track,
    DownloadProgress? progress,
    DownloadService downloads,
  ) {
    final library = ref.read(libraryProvider);
    final isDownloaded = track.localPath != null && track.localPath!.isNotEmpty;
    final liked = library.isLiked(track.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(liked ? Icons.favorite : Icons.favorite_border),
              title: Text(liked ? 'Убрать из избранного' : 'В избранное'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await library.toggleLike(track.id);
              },
            ),
            if (track.source != TrackSource.local)
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                    }
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Играть следующим'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await ref.read(audioHandlerProvider).playNext(track);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Трек будет следующим'
                        : 'Не удалось добавить в очередь'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать теги и текст'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TrackEditSheet(trackId: track.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Удалить из медиатеки'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await downloads.deleteDownload(track.id);
                await library.deleteTrack(track.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Плейлистов пока нет.\nДобавляйте радио и плейлисты кнопкой «+».',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final playlist = playlists[i];
        return Entrance(
          index: i,
          child: PressScale(
            scale: 0.98,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistScreen(
                  id: playlist.id,
                  title: playlist.title,
                  subtitle: playlist.description,
                  tracks: playlist.tracks,
                  isRadio: playlist.isRadio,
                  coverUrl: playlist.imageUrl,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  CoverArt(
                    url: playlist.imageUrl,
                    size: 56,
                    radius: 12,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${playlist.tracks.length} треков · ${formatLongDuration(playlist.totalDuration)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DownloadedTab extends ConsumerStatefulWidget {
  const _DownloadedTab({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_DownloadedTab> createState() => _DownloadedTabState();
}

class _DownloadedTabState extends ConsumerState<_DownloadedTab> {
  bool _sortBySize = false;

  Future<void> _deleteAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final downloads = ref.read(downloadProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Удалить все загрузки?'),
        content: const Text('Аудиофайлы, обложки и тексты будут удалены с устройства.'),
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
    await downloads.deleteMany(widget.tracks.map((t) => t.id));
    messenger.showSnackBar(
      const SnackBar(content: Text('Загрузки удалены')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = [...widget.tracks];
    if (_sortBySize) {
      tracks.sort((a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
    } else {
      tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Нет скачанных треков.\nСкачивайте из плейлиста или плеера.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    final totalBytes = tracks.fold<int>(0, (sum, t) => sum + _sizeOf(t));
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tracks.length} треков · ${formatBytes(totalBytes)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      formatLongDuration(totalDuration),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<bool>(
                icon: const Icon(Icons.more_horiz),
                color: AppColors.surfaceAlt,
                initialValue: _sortBySize,
                onSelected: (value) => setState(() => _sortBySize = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('По названию')),
                  PopupMenuItem(value: true, child: Text('По размеру')),
                ],
              ),
              IconButton(
                tooltip: 'Слушать всё',
                onPressed: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(tracks.first, contextQueue: tracks),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: 'Удалить все',
                onPressed: _deleteAll,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final track = tracks[i];
              return TrackTile(
                title: track.title,
                artist: track.artist,
                coverUrl: track.thumbnailUrl,
                coverPath: track.artworkPath,
                explicit: track.explicit,
                downloaded: true,
                index: i,
                trailing: Text(
                  formatBytes(_sizeOf(track)),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                onTap: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(track, contextQueue: tracks),
                onMenu: () => _menu(context, track),
              );
            },
          ),
        ),
      ],
    );
  }

  void _menu(BuildContext context, Track track) {
    final downloads = ref.read(downloadProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить скачивание'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await downloads.deleteDownload(track.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  int _sizeOf(Track track) {
    final path = track.localPath;
    if (path == null || path.isEmpty) return 0;
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : 0;
  }
}

class _TracksTab extends ConsumerWidget {
  const _TracksTab({required this.tracks, required this.emptyText});

  final List<Track> tracks;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
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
              index: i,
              onTap: () => ref
                  .read(audioHandlerProvider)
                  .playTrack(track, contextQueue: tracks),
              onMenu: () => _trackMenu(context, ref, track, progress, downloads),
            );
          },
        );
      },
    );
  }

  void _trackMenu(
    BuildContext context,
    WidgetRef ref,
    Track track,
    DownloadProgress? progress,
    DownloadService downloads,
  ) {
    final library = ref.read(libraryProvider);
    final isDownloaded = track.localPath != null && track.localPath!.isNotEmpty;
    final liked = library.isLiked(track.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(liked ? Icons.favorite : Icons.favorite_border),
              title: Text(liked ? 'Убрать из избранного' : 'В избранное'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await library.toggleLike(track.id);
              },
            ),
            if (track.source != TrackSource.local)
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
                    }
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Играть следующим'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await ref.read(audioHandlerProvider).playNext(track);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Трек будет следующим'
                        : 'Не удалось добавить в очередь'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать теги и текст'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TrackEditSheet(trackId: track.id),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Удалить из медиатеки'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await downloads.deleteDownload(track.id);
                await library.deleteTrack(track.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
