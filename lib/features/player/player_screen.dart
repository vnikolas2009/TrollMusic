import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../services/audio/audio_handler.dart';
import '../lyrics/lyrics_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.initialTrack});

  final Track? initialTrack;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showQueue = false;
  Color _dominant = const Color(0xFF282828);
  String? _colorSourceId;

  Future<void> _resolveDominant(Track track) async {
    if (_colorSourceId == track.id) return;
    _colorSourceId = track.id;

    final local = track.artworkPath;
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          FileImage(File(local)),
          size: const Size(120, 120),
        );
        _apply(palette);
        return;
      } catch (_) {}
    }

    final url = track.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(url),
          size: const Size(120, 120),
        );
        _apply(palette);
      } catch (_) {}
    }
  }

  void _apply(PaletteGenerator palette) {
    final color = palette.darkMutedColor?.color ??
        palette.dominantColor?.color ??
        palette.darkVibrantColor?.color;
    if (color != null && mounted) setState(() => _dominant = color);
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider).value ?? widget.initialTrack;
    final state = ref.watch(playbackStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final audio = ref.read(audioHandlerProvider);
    final duration = ref.watch(durationProvider).value ?? track?.duration ?? Duration.zero;

    if (track == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Ничего не играет')),
      );
    }

    _resolveDominant(track);
    final playing = state?.playing ?? false;
    final hasLyrics = ref.watch(libraryProvider).hasLyrics(track.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_dominant, AppColors.background],
            stops: const [0, 0.78],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'СЕЙЧАС ИГРАЕТ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _showQueue ? Icons.play_circle_outline : Icons.queue_music_rounded,
                    ),
                    onPressed: () => setState(() => _showQueue = !_showQueue),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showOptions(track),
                  ),
                ],
              ),
              Expanded(
                child: _showQueue
                    ? const QueueView()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            _Artwork(track: track),
                            const SizedBox(height: 26),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final liked =
                                        ref.watch(libraryProvider).isLiked(track.id);
                                    return IconButton(
                                      icon: Icon(
                                        liked ? Icons.favorite : Icons.favorite_border,
                                        color: liked ? AppColors.accent : AppColors.textSecondary,
                                      ),
                                      onPressed: () async {
                                        await ref.read(libraryProvider).toggleLike(track.id);
                                        if (context.mounted) setState(() {});
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Slider(
                              value: position.inMilliseconds
                                  .clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds)
                                  .toDouble(),
                              max: duration.inMilliseconds == 0
                                  ? 1
                                  : duration.inMilliseconds.toDouble(),
                              onChanged: (v) => audio.seek(Duration(milliseconds: v.toInt())),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    formatDuration(position),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    formatDuration(duration),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle_rounded),
                                  color: audio.shuffleEnabled.value
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  onPressed: () async {
                                    await audio.setShuffle(!audio.shuffleEnabled.value);
                                    setState(() {});
                                  },
                                ),
                                IconButton(
                                  iconSize: 32,
                                  icon: const Icon(Icons.skip_previous_rounded),
                                  onPressed: audio.skipToPrevious,
                                ),
                                _PlayButton(
                                  playing: playing,
                                  onTap: () => playing ? audio.pause() : audio.play(),
                                ),
                                IconButton(
                                  iconSize: 32,
                                  icon: const Icon(Icons.skip_next_rounded),
                                  onPressed: audio.skipToNext,
                                ),
                                IconButton(
                                  icon: Icon(
                                    switch (audio.repeat.value) {
                                      YsRepeat.one => Icons.repeat_one_rounded,
                                      YsRepeat.all => Icons.repeat_rounded,
                                      YsRepeat.off => Icons.repeat_rounded,
                                    },
                                  ),
                                  color: audio.repeat.value == YsRepeat.off
                                      ? AppColors.textSecondary
                                      : AppColors.accent,
                                  onPressed: () async {
                                    await audio.cycleRepeat();
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            _LyricsCard(
                              trackId: track.id,
                              hasLyrics: hasLyrics,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LyricsScreen(trackId: track.id),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptions(Track track) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(
                track.localPath != null && track.localPath!.isNotEmpty
                    ? 'Удалить скачивание'
                    : 'Скачать трек',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final downloads = ref.read(downloadProvider);
                if (track.localPath != null && track.localPath!.isNotEmpty) {
                  await downloads.deleteDownload(track.id);
                } else {
                  await downloads.download(track);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Готово')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Таймер сна'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSleepTimer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Кроссфейд'),
              trailing: Text(
                '${ref.read(audioHandlerProvider).crossfade.value.inSeconds} с',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCrossfade();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimer() {
    const options = <int>[0, 5, 15, 30, 60];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Таймер сна', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final minutes in options)
              ListTile(
                title: Text(minutes == 0 ? 'Выключить' : '$minutes мин'),
                onTap: () {
                  final audio = ref.read(audioHandlerProvider);
                  if (minutes == 0) {
                    audio.cancelSleepTimer();
                  } else {
                    audio.startSleepTimer(Duration(minutes: minutes));
                  }
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showCrossfade() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Кроссфейд', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final seconds in <int>[0, 3, 6, 10, 12])
              ListTile(
                title: Text(seconds == 0 ? 'Выключен' : '$seconds с'),
                onTap: () {
                  ref
                      .read(audioHandlerProvider)
                      .setCrossfade(Duration(seconds: seconds));
                  Navigator.pop(sheetContext);
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final path = track.artworkPath;
    final url = track.thumbnailUrl;
    Widget child;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      child = Image.file(File(path), fit: BoxFit.cover);
    } else if (url != null && url.isNotEmpty) {
      child = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceHigh,
        child: const Icon(Icons.music_note_rounded, size: 64, color: AppColors.textSecondary),
      );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.textPrimary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 34,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _LyricsCard extends StatelessWidget {
  const _LyricsCard({required this.trackId, required this.hasLyrics, required this.onTap});

  final String trackId;
  final bool hasLyrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.lyrics_outlined, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Текст песни',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLyrics ? 'Синхронизированный · нажмите' : 'Текст не найден · нажмите',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioHandlerProvider);
    return StreamBuilder<List<MediaItem>>(
      stream: audio.queue,
      initialData: audio.queue.value,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MediaItem>[];
        if (items.isEmpty) {
          return const Center(
            child: Text('Очередь пуста', style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        final current = audio.player.currentIndex ?? 0;
        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          onReorder: (oldIndex, newIndex) {
            final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
            audio.reorder(oldIndex, target);
          },
          itemBuilder: (context, i) {
            final item = items[i];
            final active = i == current;
            return ListTile(
              key: ValueKey('${item.id}-$i'),
              leading: Icon(
                active ? Icons.graphic_eq_rounded : Icons.drag_handle,
                color: active ? AppColors.accent : AppColors.textSecondary,
                size: 18,
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                item.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              trailing: Text(
                formatDuration(item.duration ?? Duration.zero),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              onTap: () => audio.playAt(i),
            );
          },
        );
      },
    );
  }
}
