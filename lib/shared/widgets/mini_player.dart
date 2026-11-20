import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final state = ref.watch(playbackStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    if (track == null) return const SizedBox.shrink();

    final playing = state?.playing ?? false;
    final duration = track.duration.inMilliseconds > 0
        ? track.duration
        : (state?.updatePosition != null ? track.duration : Duration.zero);
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -200) onTap?.call();
      },
      child: Container(
        height: 58,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceMini,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: _Cover(track: track),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => playing
                        ? ref.read(audioHandlerProvider).pause()
                        : ref.read(audioHandlerProvider).play(),
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: const AlwaysStoppedAnimation(AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track});

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
        errorBuilder: (_, __, ___) => _fallback(),
      );
    } else {
      child = _fallback();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 44, height: 44, child: child),
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
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
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
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          IconButton(
                            iconSize: 18,
                            icon: const Icon(Icons.close, color: AppColors.textSecondary),
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
