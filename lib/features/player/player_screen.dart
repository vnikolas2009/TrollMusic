import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:palette_generator/palette_generator.dart';

import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/appearance.dart';
import '../../core/utils/track_swipe.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../services/audio/audio_handler.dart';
import '../../shared/widgets/heart_button.dart';
import '../../shared/widgets/jelly_slider.dart';
import '../library/track_list_screen.dart';
import '../lyrics/lyrics_screen.dart';
import 'lyric_preview.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, this.initialTrack});

  final Track? initialTrack;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  String _countdown(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

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
    final audio = ref.read(audioHandlerProvider);

    if (track == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Ничего не играет')),
      );
    }

    _resolveDominant(track);
    final playing = state?.playing ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 260) {
            Navigator.of(context).maybePop();
          }
        },
        child: AnimatedContainer(
          duration: AppMotion.slower,
          curve: AppMotion.emphasized,
          decoration: BoxDecoration(
            // Однотонная подложка: тон обложки поверх фона темы.
            color: Color.alphaBlend(
              AppColors.tinted(_dominant).withValues(
                alpha: (0.3 * AppAppearance.fx).clamp(0.0, 0.5).toDouble(),
              ),
              AppColors.background,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Заголовок центрируется по экрану независимо от числа кнопок
                // по краям: кнопки лежат поверх, а у текста по бокам запас
                // под две кнопки (2 × 48).
                SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 96),
                        child: ValueListenableBuilder<Duration?>(
                          valueListenable:
                              ref.read(audioHandlerProvider).sleepRemaining,
                          builder: (context, remaining, _) => FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              remaining == null
                                  ? 'СЕЙЧАС ИГРАЕТ'
                                  : 'ТАЙМЕР СНА · ${_countdown(remaining)}',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                color: remaining == null
                                    ? AppColors.textSecondary
                                    : AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              _showQueue
                                  ? Icons.play_circle_outline
                                  : Icons.queue_music_rounded,
                            ),
                            onPressed: () =>
                                setState(() => _showQueue = !_showQueue),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showOptions(track),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppMotion.base,
                    switchInCurve: AppMotion.enter,
                    child: _showQueue
                        ? const QueueView(key: ValueKey('queue'))
                        : SingleChildScrollView(
                            key: const ValueKey('player'),
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                const SizedBox(height: 12),
                                // Свайп по обложке — следующий/предыдущий трек.
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragEnd: (details) {
                                    switch (trackSwipeFor(
                                      details.primaryVelocity,
                                    )) {
                                      case TrackSwipe.next:
                                        HapticFeedback.selectionClick();
                                        audio.skipToNext();
                                      case TrackSwipe.previous:
                                        HapticFeedback.selectionClick();
                                        audio.skipToPrevious();
                                      case TrackSwipe.none:
                                        break;
                                    }
                                  },
                                  child: _Artwork(track: track, playing: playing),
                                ),
                                LyricPreview(trackId: track.id),
                                const SizedBox(height: 26),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          GestureDetector(
                                            onTap: () =>
                                                Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => TrackListScreen.artist(
                                                  name: track.artist,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              track.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final liked = ref
                                            .watch(libraryProvider)
                                            .isLiked(track.id);
                                        return HeartButton(
                                          liked: liked,
                                          onPressed: () async {
                                            await ref
                                                .read(libraryProvider)
                                                .toggleLike(track.id);
                                            if (context.mounted) {
                                              setState(() {});
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _SeekBar(fallbackDuration: track.duration),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.shuffle_rounded),
                                      color: audio.shuffleEnabled.value
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                      onPressed: () async {
                                        await audio.setShuffle(
                                          !audio.shuffleEnabled.value,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                    IconButton(
                                      iconSize: 32,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                      onPressed: audio.skipToPrevious,
                                    ),
                                    _PlayButton(
                                      playing: playing,
                                      onTap: () =>
                                          playing ? audio.pause() : audio.play(),
                                    ),
                                    IconButton(
                                      iconSize: 32,
                                      icon: const Icon(Icons.skip_next_rounded),
                                      onPressed: audio.skipToNext,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        switch (audio.repeat.value) {
                                          TrollRepeat.one =>
                                            Icons.repeat_one_rounded,
                                          TrollRepeat.all =>
                                            Icons.repeat_rounded,
                                          TrollRepeat.off =>
                                            Icons.repeat_rounded,
                                        },
                                      ),
                                      color: audio.repeat.value ==
                                              TrollRepeat.off
                                          ? AppColors.textSecondary
                                          : AppColors.accent,
                                      onPressed: () async {
                                        await audio.cycleRepeat();
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (state?.processingState ==
                                        AudioProcessingState.loading ||
                                    state?.processingState ==
                                        AudioProcessingState.buffering)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 10),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                if (state?.processingState ==
                                    AudioProcessingState.error)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _StreamErrorBanner(
                                      onRetry: () => audio.playTrack(track),
                                    ),
                                  ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
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
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Таймер сна'),
              trailing: ValueListenableBuilder<Duration?>(
                valueListenable: ref.read(audioHandlerProvider).sleepRemaining,
                builder: (context, remaining, _) => remaining == null
                    ? const SizedBox.shrink()
                    : Text(
                        _countdown(remaining),
                        style: TextStyle(color: AppColors.accent),
                      ),
              ),
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
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCrossfade();
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Скорость'),
              trailing: Text(
                '${ref.read(audioHandlerProvider).player.speed.toStringAsFixed(2)}×',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSpeed();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Добавить в плейлист'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addToPlaylist(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Играть следующим'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await ref.read(audioHandlerProvider).playNext(track);
                if (!mounted) return;
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
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('В очередь'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await ref.read(audioHandlerProvider).addToQueue(track);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Добавлено в конец очереди'
                        : 'Не удалось добавить в очередь'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Информация о треке'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showInfo(track);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeed() {
    const options = <double>[0.75, 1, 1.25, 1.5, 2];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) {
        final speed = ref.read(audioHandlerProvider).player.speed;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Скорость',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final value in options)
                ListTile(
                  title: Text(value == 1 ? 'Обычная' : '${value}×'),
                  trailing: (speed - value).abs() < 0.01
                      ? Icon(Icons.check, color: AppColors.accent, size: 18)
                      : null,
                  onTap: () {
                    ref.read(audioHandlerProvider).setSpeed(value);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addToPlaylist(Track track) async {
    final library = ref.read(libraryProvider);
    final playlists = library.playlists;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала создайте плейлист в медиатеке')),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Добавить в плейлист',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final playlist = playlists[i];
                  return ListTile(
                    title: Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${playlist.tracks.length} треков',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => Navigator.pop(sheetContext, playlist.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    final playlist = library.playlistById(selected);
    if (playlist == null) return;
    if (playlist.tracks.any((t) => t.id == track.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Трек уже в плейлисте')),
      );
      return;
    }
    await library.savePlaylist(
      playlist.copyWith(tracks: [...playlist.tracks, track]),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено в «${playlist.title}»')),
    );
  }

  void _showInfo(Track track) {
    final duration = track.duration == Duration.zero
        ? '—'
        : formatDuration(track.duration);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Информация о треке',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _infoRow('Название', track.title),
              _infoRow('Исполнитель', track.artist),
              if (track.album.isNotEmpty) _infoRow('Альбом', track.album),
              _infoRow('Длительность', duration),
              if (track.bitrate != null)
                _infoRow('Битрейт', '${track.bitrate} kbps'),
              _infoRow(
                'Текст',
                ref.read(libraryProvider).hasLyrics(track.id) ? 'Есть' : 'Нет',
              ),
              if (track.localPath != null)
                _infoRow('Файл', p.extension(track.localPath!).replaceFirst('.', '').toUpperCase()),
              if (track.sourcePath != null) _infoRow('Откуда', track.sourcePath!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showSleepTimer() {
    const options = <int>[0, 5, 15, 30, 45, 60, 90];
    final audio = ref.read(audioHandlerProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Таймер сна',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('До конца трека'),
                onTap: () {
                  audio.sleepAfterCurrentTrack();
                  Navigator.pop(sheetContext);
                },
              ),
              for (final minutes in options)
                ListTile(
                  title: Text(minutes == 0 ? 'Выключить' : '$minutes мин'),
                  onTap: () {
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
              child: Text(
                'Кроссфейд',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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

class _StreamErrorBanner extends StatelessWidget {
  const _StreamErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Поток недоступен. Попробуйте ещё раз или другой трек.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

/// Ползунок и таймеры: единственная часть экрана, которая слушает
/// positionProvider/durationProvider, поэтому остальной экран не
/// перестраивается на каждый тик позиции.
class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.fallbackDuration});

  final Duration fallbackDuration;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  /// Справа показывается оставшееся время; переключается нажатием на него и
  /// запоминается.
  late bool _remaining = ref.read(settingsProvider).showRemainingTime;

  void _toggleRemaining() {
    setState(() => _remaining = !_remaining);
    ref.read(settingsProvider).showRemainingTime = _remaining;
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(durationProvider).value ?? widget.fallbackDuration;
    final labelStyle = TextStyle(
      fontSize: 11,
      color: AppColors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return RepaintBoundary(
      child: Column(
        children: [
          JellySlider(
            position: position,
            duration: duration,
            onChanged: (value) {
              ref.read(audioHandlerProvider).seek(value);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(position), style: labelStyle),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleRemaining,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      _remaining
                          ? formatRemaining(position, duration)
                          : formatDuration(duration),
                      style: labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track, required this.playing});

  final Track track;

  /// На паузе обложка плавно уменьшается, при воспроизведении возвращается.
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final path = track.artworkPath;
    Widget child;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: AppConfig.coverCacheWidth,
      );
    } else {
      child = _placeholder();
    }
    return AnimatedScale(
      scale: playing ? 1.0 : 0.92,
      duration: AppMotion.slow,
      curve: AppMotion.emphasized,
      child: AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppAppearance.coverRadius(22)),
          boxShadow: AppAppearance.shadows(
            blur: 36,
            offset: const Offset(0, 18),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppAppearance.coverRadius(22)),
          child: AnimatedSwitcher(
            duration: AppMotion.slow,
            switchInCurve: AppMotion.enter,
            child: KeyedSubtree(
              key: ValueKey(track.id),
              child: child,
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceHigh,
        child: Icon(
          Icons.music_note_rounded,
          size: 64,
          color: AppColors.textSecondary,
        ),
      );
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  /// Мягкое кольцо вокруг кнопки, пока играет музыка.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_PlayButton old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    final enabled = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (enabled && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!enabled && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final t = _pulse.value;
              return Opacity(
                opacity: t == 0 ? 0 : (1 - t) * 0.28,
                child: Transform.scale(
                  scale: 1 + 0.45 * Curves.easeOut.transform(t),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _button(),
      ],
    );
  }

  Widget _button() {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: _pressed ? AppMotion.instant : AppMotion.base,
        curve: _pressed ? AppMotion.exit : AppMotion.press,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
            boxShadow: AppAppearance.shadows(
              blur: 24,
              offset: const Offset(0, 10),
            ),
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.instant,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
            child: Icon(
              widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(widget.playing),
              size: 34,
              color: Colors.black,
            ),
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
          return Center(
            child: Text(
              'Очередь пуста',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        final current = audio.player.currentIndex ?? 0;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Далее · ${items.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: AppColors.surfaceAlt,
                          title: const Text('Очистить очередь?'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Очистить'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await audio.clearQueue();
                    },
                    child: const Text('Очистить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) {
                  final target =
                      newIndex > oldIndex ? newIndex - 1 : newIndex;
                  audio.reorder(oldIndex, target);
                },
                itemBuilder: (context, i) {
                  final item = items[i];
                  final active = i == current;
                  return ListTile(
                    key: ValueKey('${item.id}-$i'),
                    leading: Icon(
                      active ? Icons.graphic_eq_rounded : Icons.drag_handle,
                      color:
                          active ? AppColors.accent : AppColors.textSecondary,
                      size: 18,
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w400,
                        color:
                            active ? AppColors.accent : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      item.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatDuration(item.duration ?? Duration.zero),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        IconButton(
                          iconSize: 18,
                          icon: Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => audio.removeFromQueue(i),
                        ),
                      ],
                    ),
                    onTap: () => audio.playAt(i),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
