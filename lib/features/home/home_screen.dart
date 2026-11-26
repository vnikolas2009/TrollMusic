import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lyrics_job.dart';
import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../app/tab_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/track_groups.dart';
import '../../core/utils/track_sort.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/brand_wordmark.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/tab_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final library = ref.watch(libraryProvider);
    final settings = ref.watch(settingsProvider);
    final audio = ref.read(audioHandlerProvider);
    final current = ref.watch(currentTrackProvider).value;
    final job = ref.watch(lyricsJobProvider);

    final byId = {for (final t in tracks) t.id: t};
    final recent = sortTracks(tracks, TrackSort.recent).take(20).toList();
    final played = [
      for (final id in settings.recentIds)
        if (byId[id] != null) byId[id]!,
    ].take(20).toList();
    final counts = settings.playCounts;
    final top = sortTracks(tracks, TrackSort.mostPlayed, playCounts: counts)
        .where((t) => (counts[t.id] ?? 0) > 1)
        .take(20)
        .toList();
    final daily = buildDailyPick(tracks, settings.recentIds);
    final missing = tracks.where((t) => !library.hasLyrics(t.id)).length;
    final last = byId[settings.lastTrackId];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        const SliverToBoxAdapter(
          child: TabHeader(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BrandMark(),
                SizedBox(width: 10),
                BrandWordmark(fontSize: 26),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: tracks.isEmpty
              ? _EmptyLibrary(
                  onImport: () =>
                      ref.read(selectedTabProvider.notifier).select(AppTab.create),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: () => audio.playShuffled(tracks),
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Вся музыка вперемешку'),
                          ),
                          if (last != null && current == null)
                            FilledButton.tonalIcon(
                              onPressed: () => audio.playTrack(last, contextQueue: tracks),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Продолжить'),
                            ),
                        ],
                      ),
                    ),
                    if (missing > 0 || job.running)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _LyricsCard(missing: missing, job: job),
                      ),
                    if (daily.isNotEmpty)
                      Entrance(
                        index: 0,
                        child: _Rail(title: 'Подборка дня', subtitle: 'Меняется каждый день', tracks: daily, all: tracks),
                      ),
                    if (recent.isNotEmpty)
                      Entrance(
                        index: 1,
                        child: _Rail(title: 'Недавно добавлено', tracks: recent, all: tracks),
                      ),
                    if (played.isNotEmpty)
                      Entrance(
                        index: 2,
                        child: _Rail(title: 'Недавно слушали', tracks: played, all: tracks),
                      ),
                    if (top.isNotEmpty)
                      Entrance(
                        index: 3,
                        child: _Rail(title: 'Часто слушаете', tracks: top, all: tracks),
                      ),
                    const SizedBox(height: 96),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Icon(Icons.library_music_rounded, size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          const Text(
            'Здесь будет ваша музыка',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Добавьте файлы или папку с музыкой — обложки, теги и тексты '
            'подтянутся сами.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Импортировать музыку'),
          ),
        ],
      ),
    );
  }
}

/// Карточка с итогом по текстам: сколько треков без текста и кнопка поиска.
class _LyricsCard extends ConsumerWidget {
  const _LyricsCard({required this.missing, required this.job});

  final int missing;
  final LyricsJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(lyricsJobProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.lyrics_outlined, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.running
                      ? 'Ищу тексты: ${job.done} из ${job.total}'
                      : 'Без текста: $missing',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  job.running
                      ? 'Найдено: ${job.found}'
                      : '5 источников, приоритет у enhanced LRC',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: job.running ? ctl.cancel : ctl.runMissing,
            child: Text(job.running ? 'Стоп' : 'Найти'),
          ),
        ],
      ),
    );
  }
}

class _Rail extends ConsumerWidget {
  const _Rail({
    required this.title,
    required this.tracks,
    required this.all,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Track> tracks;
  final List<Track> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.read(audioHandlerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: subtitle),
        _HorizontalRail(
          height: 188,
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final track = tracks[i];
            return SizedBox(
              width: 132,
              child: _TrackCard(
                track: track,
                size: 132,
                index: i,
                onTap: () => audio.playTrack(track, contextQueue: tracks),
                onLongPress: () => showTrackActions(context, ref, track),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Логотип-«эквалайзер» с мягким свечением акцента.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: AppColors.accent,
        size: 18,
      ),
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Карточка трека: нажатие сжимает обложку, поверх — лёгкий градиент.
class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.size,
    this.index = 0,
    this.titleOverride,
    this.subtitleOverride,
    this.onTap,
    this.onLongPress,
  });

  final Track track;
  final double size;
  final int index;
  final String? titleOverride;
  final String? subtitleOverride;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Entrance(
      index: index,
      offsetY: 0.08,
      child: PressScale(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                CoverArt(
                  path: track.artworkPath,
                  size: size,
                  radius: 14,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              titleOverride ?? track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitleOverride ?? track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

