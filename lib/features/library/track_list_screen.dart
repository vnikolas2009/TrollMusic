import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/track_groups.dart';
import '../../core/utils/track_sort.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/mini_player_bar.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';

/// Список треков с шапкой: исполнитель, альбом или любая подборка.
/// Содержимое пересчитывается при изменении медиатеки.
class TrackListScreen extends ConsumerWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    required this.select,
    this.subtitle,
  });

  factory TrackListScreen.artist({Key? key, required String name}) =>
      TrackListScreen(
        key: key,
        title: name,
        subtitle: 'Исполнитель',
        select: (all) => sortTracks(tracksByArtist(all, name), TrackSort.album),
      );

  factory TrackListScreen.album({Key? key, required String name}) =>
      TrackListScreen(
        key: key,
        title: name,
        subtitle: 'Альбом',
        select: (all) => all.where((t) => t.album.trim() == name).toList(),
      );

  final String title;
  final String? subtitle;
  final List<Track> Function(List<Track> all) select;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(tracksProvider).value ?? const <Track>[];
    final library = ref.watch(libraryProvider);
    final current = ref.watch(currentTrackProvider).value;
    final audio = ref.read(audioHandlerProvider);

    final tracks = select(all);
    final total = tracks.fold<Duration>(Duration.zero, (s, t) => s + t.duration);

    return Scaffold(
      bottomNavigationBar: const MiniPlayerBar(),
      appBar: AppBar(
        backgroundColor: AppColors.appBarBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('Здесь пока пусто'))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        CoverMosaic(
                          paths: tracks.map((t) => t.artworkPath).toList(),
                          size: 96,
                          radius: 16,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (subtitle != null)
                                Text(subtitle!, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                ),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final track = tracks[i];
                    return TrackTile(
                      title: track.title,
                      artist: track.artist,
                      coverPath: track.artworkPath,
                      active: current?.id == track.id,
                      hasLyrics: library.hasLyrics(track.id),
                      subtitleExtra: track.duration == Duration.zero
                          ? null
                          : formatDuration(track.duration),
                      onTap: () => audio.playTrack(track, contextQueue: tracks),
                      onMenu: () => showTrackActions(context, ref, track),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
    );
  }
}
