import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/station_card.dart';
import '../../shared/widgets/section_header.dart';
import '../playlist/playlist_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background,
          title: const Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 22),
              SizedBox(width: 8),
              Text('YSPlayer'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tracks.isNotEmpty) _DailyPick(tracks: tracks.take(12).toList()),
              _Stations(tracks: tracks),
              if (tracks.isNotEmpty) _Recent(tracks: tracks),
              _Discoveries(tracks: tracks),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyPick extends StatelessWidget {
  const _DailyPick({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final lead = tracks.first;
    final artists = tracks.map((t) => t.artist).toSet().take(3).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Подборка дня',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistScreen(
                  id: 'daily',
                  title: 'Подборка дня',
                  subtitle: artists,
                  tracks: tracks,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2.1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(
                      url: lead.thumbnailUrl,
                      path: lead.artworkPath,
                      size: 400,
                      radius: 0,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'ТВОЙ\nМИКС',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 30,
                              height: 0.95,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Recent extends ConsumerStatefulWidget {
  const _Recent({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_Recent> createState() => _RecentState();
}

class _RecentState extends ConsumerState<_Recent> {
  int _revision = 0;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Очистить историю?'),
        content: const Text('Рекомендации и станции начнутся заново.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(settingsProvider).clearHistory();
    setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final byId = {for (final t in widget.tracks) t.id: t};
    final recent = settings.recentIds
        .map((id) => byId[id])
        .whereType<Track>()
        .take(10)
        .toList();
    if (recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Недавно слушали',
          action: TextButton(
            onPressed: _clear,
            child: const Text('Очистить'),
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            key: ValueKey(_revision),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final track = recent[i];
              final plays = settings.playCounts[track.id] ?? 0;
              return SizedBox(
                width: 104,
                child: InkWell(
                  onTap: () => ref
                      .read(audioHandlerProvider)
                      .playTrack(track, contextQueue: recent),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(
                        url: track.thumbnailUrl,
                        path: track.artworkPath,
                        size: 104,
                        radius: 8,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        plays > 1 ? '${track.artist} · $plays раз' : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Stations extends StatelessWidget {
  const _Stations({required this.tracks});

  final List<Track> tracks;

  static const _palette = [
    AppColors.stationYellow,
    AppColors.stationPink,
    AppColors.stationMint,
    AppColors.stationLilac,
    AppColors.stationPeach,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Рекомендуемые станции'),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final a = tracks.isEmpty ? null : tracks[i % tracks.length];
              final b = tracks.length > 1 ? tracks[(i + 1) % tracks.length] : null;
              final c = tracks.length > 2 ? tracks[(i + 2) % tracks.length] : null;
              final name = a == null ? 'Радио ${i + 1}' : a.artist.split(',').first.trim();
              return StationCard(
                title: name,
                background: _palette[i % _palette.length],
                centerUrl: a?.thumbnailUrl,
                leftUrl: b?.thumbnailUrl,
                rightUrl: c?.thumbnailUrl,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(
                      id: 'station:$i',
                      title: '$name: радио',
                      isRadio: true,
                      tracks: tracks.isEmpty
                          ? const []
                          : List.generate(20, (k) => tracks[(i + k) % tracks.length]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Discoveries extends StatelessWidget {
  const _Discoveries({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
        child: Text(
          'Медиатека пуста.\nИмпортируйте аудио во вкладке «Создать»\nили найдите музыку в «Поиске».',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
      );
    }

    final items = tracks.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Еще больше открытий',
          avatarUrl: items.first.thumbnailUrl,
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final track = items[i];
              return SizedBox(
                width: 132,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistScreen(
                        id: 'mix:${track.id}',
                        title: track.artist,
                        tracks: [track],
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(url: track.thumbnailUrl, path: track.artworkPath, size: 132, radius: 8),
                      const SizedBox(height: 8),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Text(
            _summary(tracks),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  String _summary(List<Track> list) {
    var total = Duration.zero;
    for (final track in list) {
      total += track.duration;
    }
    return '${list.length} треков · ${formatLongDuration(total)}';
  }
}
