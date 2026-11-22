import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/track_groups.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/track_tile.dart';

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(tracksProvider).value ?? const <Track>[];
    final own = tracksByArtist(all, name)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final albums = <String>{
      for (final track in own)
        if (track.album.trim().isNotEmpty) track.album.trim(),
    };
    final total = own.fold<Duration>(Duration.zero, (s, t) => s + t.duration);
    final lead = own.isEmpty ? null : own.first;
    final audio = ref.read(audioHandlerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 316,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              titlePadding: const EdgeInsetsDirectional.only(
                start: 56,
                bottom: 14,
                end: 16,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.surfaceHigh, AppColors.background],
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Center(
                      child: PressScale(
                        scale: 0.97,
                        child: CoverArt(
                          url: lead?.thumbnailUrl,
                          path: lead?.artworkPath,
                          size: 152,
                          radius: 999,
                          circle: true,
                          placeholderIcon: Icons.person_rounded,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (own.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'В медиатеке нет треков этого исполнителя.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.6),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Text(
                      albums.isEmpty
                          ? 'Исполнитель'
                          : 'Альбомы: ${albums.take(3).join(' · ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Text(
                      '${own.length} треков · ${formatLongDuration(total)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.textPrimary,
                          foregroundColor: Colors.black,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () =>
                            audio.playTrack(own.first, contextQueue: own),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Слушать',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: own.length,
              itemBuilder: (context, i) {
                final track = own[i];
                return TrackTile(
                  title: track.title,
                  artist: track.album.isEmpty ? track.artist : track.album,
                  coverUrl: track.thumbnailUrl,
                  coverPath: track.artworkPath,
                  explicit: track.explicit,
                  downloaded:
                      track.localPath != null && track.localPath!.isNotEmpty,
                  index: i,
                  onTap: () => audio.playTrack(track, contextQueue: own),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ],
      ),
    );
  }
}
