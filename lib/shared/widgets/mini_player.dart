import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/track_swipe.dart';
import '../../core/theme/appearance.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';

/// Мини-плеер: стеклянная плашка, которая плавно появляется и умеет
/// свайпнуться вверх, чтобы открыть полноэкранный плеер.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final state = ref.watch(playbackStateProvider).value;

    if (track == null) {
      // Тот же AnimatedSize, что и ниже: при появлении трека плашка
      // «вырастает» из нулевой высоты, а не возникает рывком.
      return AnimatedSize(
        duration: AppMotion.slow,
        curve: AppMotion.emphasized,
        alignment: Alignment.bottomCenter,
        child: const SizedBox(width: double.infinity),
      );
    }

    final playing = state?.playing ?? false;
    final buffering = state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;

    return AnimatedSize(
      duration: AppMotion.slow,
      curve: AppMotion.emphasized,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        onTap: onTap,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -200) onTap?.call();
        },
        // Свайп вправо/влево по панели — предыдущий/следующий трек.
        onHorizontalDragEnd: (details) {
          final audio = ref.read(audioHandlerProvider);
          switch (trackSwipeFor(details.primaryVelocity)) {
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
        child: Container(
          height: 62,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMini,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outline),
            boxShadow: AppAppearance.shadows(
              blur: 22,
              offset: const Offset(0, 6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _Cover(track: track),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSwitcher(
                            duration: AppMotion.base,
                            child: Text(
                              track.title,
                              key: ValueKey(track.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (buffering)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: () => playing
                            ? ref.read(audioHandlerProvider).pause()
                            : ref.read(audioHandlerProvider).play(),
                        icon: AnimatedSwitcher(
                          duration: AppMotion.instant,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          ),
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(playing),
                            size: 30,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              _MiniProgress(duration: track.duration),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полоса прогресса: единственный виджет, который слушает `positionProvider`.
class _MiniProgress extends ConsumerWidget {
  const _MiniProgress({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: AppColors.surfaceHigh,
      valueColor: AlwaysStoppedAnimation(AppColors.textPrimary),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final path = track.artworkPath;
    Widget child;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: AppConfig.thumbCacheWidth,
      );
    } else {
      child = _fallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 46, height: 46, child: child),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.surfaceHigh,
        child: const Icon(Icons.music_note_rounded, size: 20),
      );
}

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(audioHandlerProvider).queue;
    return StreamBuilder<List<MediaItem>>(
      stream: queue,
      initialData: queue.value,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MediaItem>[];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    const Text(
                      'Очередь',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (items.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            ref.read(audioHandlerProvider).clearQueue(),
                        child: const Text('Очистить'),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  onReorder: (oldIndex, newIndex) {
                    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
                    ref
                        .read(audioHandlerProvider)
                        .reorder(oldIndex, target);
                  },
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final duration = item.duration;
                    return ListTile(
                      key: ValueKey(item.id),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatDuration(duration),
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          IconButton(
                            iconSize: 18,
                            icon: Icon(Icons.close, color: AppColors.textSecondary),
                            onPressed: () =>
                                ref.read(audioHandlerProvider).removeFromQueue(index),
                          ),
                        ],
                      ),
                      onTap: () => ref.read(audioHandlerProvider).playAt(index),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
