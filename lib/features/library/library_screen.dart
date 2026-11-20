import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/track_tile.dart';
import '../playlist/playlist_screen.dart';
import '../settings/settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  static const _labels = ['Плейлисты', 'Скачанные', 'Локальные', 'Избранное'];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final downloaded = ref.watch(downloadedProvider).value ?? const <Track>[];
    final local = ref.watch(localTracksProvider).value ?? const <Track>[];
    final liked = ref.watch(likedProvider).value ?? const <Track>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Медиатека',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorColor: AppColors.textPrimary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: _labels.map((l) => Tab(text: l)).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PlaylistsTab(playlists: playlists),
              _TracksTab(
                tracks: downloaded,
                emptyText: 'Нет скачанных треков.\nСкачивайте из плейлиста или плеера.',
              ),
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

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const Center(
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final playlist = playlists[i];
        return ListTile(
          leading: CoverArt(
            url: playlist.imageUrl,
            size: 52,
            radius: 4,
          ),
          title: Text(
            playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${playlist.tracks.length} треков · ${formatLongDuration(playlist.totalDuration)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
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
        );
      },
    );
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
            style: const TextStyle(color: AppColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final track = tracks[i];
        return TrackTile(
          title: track.title,
          artist: track.artist,
          coverUrl: track.thumbnailUrl,
          coverPath: track.artworkPath,
          explicit: track.explicit,
          downloaded: track.localPath != null && track.localPath!.isNotEmpty,
          onTap: () => ref.read(audioHandlerProvider).playTrack(track, contextQueue: tracks),
        );
      },
    );
  }
}
