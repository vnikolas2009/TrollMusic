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

  @override
  void initState() {
    super.initState();
    _resolveColor();
  }

  Future<void> _resolveColor() async {
    final url = widget.coverUrl ?? widget.tracks.firstOrNull?.thumbnailUrl;
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
    final tracks = widget.tracks;
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
                          widget.title,
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
                          widget.subtitle ??
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
                              icon: Icons.add,
                              onTap: () async {
                                final library = ref.read(libraryProvider);
                                await library.savePlaylist(
                                  Playlist(
                                    id: widget.id,
                                    title: widget.title,
                                    description: widget.subtitle ?? '',
                                    imageUrl: widget.coverUrl ?? lead?.thumbnailUrl,
                                    tracks: tracks,
                                    isRadio: widget.isRadio,
                                    colorValue: _dominant.value,
                                  ),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Добавлено в медиатеку')),
                                  );
                                }
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
