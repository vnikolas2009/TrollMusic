import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../app/tab_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/track_groups.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/brand_wordmark.dart';
import '../settings/network_diagnostics_screen.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/press_scale.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/station_card.dart';
import '../playlist/playlist_screen.dart';
import '../../app/source_provider.dart';
import '../../core/utils/spotify_link.dart';
import '../../shared/widgets/source_switcher.dart';
import 'music_sections.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider).value ?? const <Track>[];
    final settings = ref.watch(settingsProvider);
    final daily = buildDailyPick(tracks, settings.recentIds);
    final source = ref.watch(musicSourceProvider);
    final tokens = ref.watch(serviceTokensProvider);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          // Прозрачная, пока контент не под ней: иначе верх экрана — чёрная
          // плашка, закрывающая градиент фона.
          backgroundColor: AppColors.appBarBackground,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: const Row(
            children: [
              _BrandMark(),
              SizedBox(width: 10),
              BrandWordmark(fontSize: 21),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: SourceSwitcher(
                  selected: source,
                  onChanged: (value) =>
                      ref.read(musicSourceProvider.notifier).select(value),
                ),
              ),
              ...switch (source) {
                MusicSource.spotify => <Widget>[
                    const _SpotifyLinkField(),
                    _TrendingSection(
                      provider: spotifyTrendingProvider,
                      title: 'Популярное в Spotify',
                      subtitle: 'Чарты и хиты',
                    ),
                  ],
                MusicSource.youtube => <Widget>[
                    if (daily.isNotEmpty)
                      Entrance(index: 0, child: _DailyPick(tracks: daily)),
                    _TrendingSection(
                      provider: trendingProvider,
                      title: 'Популярная музыка',
                      subtitle: 'YouTube Music · сейчас слушают',
                    ),
                  ],
                MusicSource.yandex => <Widget>[
                    _TrendingSection(
                      provider: yandexTrendingProvider,
                      title: 'Чарт Яндекс Музыки',
                      subtitle: tokens.hasYandex
                          ? 'Прямой звук с вашим токеном'
                          : 'Звук подбирается на других источниках',
                    ),
                  ],
                MusicSource.vk => <Widget>[
                    if (tokens.hasVk)
                      _TrendingSection(
                        provider: vkTrendingProvider,
                        title: 'VK Музыка',
                        subtitle: 'Подборка из вашего аккаунта',
                      )
                    else
                      _ConnectCard(
                        title: 'Подключите VK Музыку',
                        message:
                            'VK отдаёт музыку только по личному токену. '
                            'Добавьте его в настройках — без токена этот '
                            'источник недоступен.',
                        onTap: () => ref
                            .read(selectedTabProvider.notifier)
                            .select(AppTab.settings),
                      ),
                  ],
                MusicSource.audius => <Widget>[
                    _TrendingSection(
                      provider: audiusTrendingProvider,
                      title: 'Тренды Audius',
                      subtitle: 'Независимые артисты · за неделю',
                    ),
                  ],
              },
              if (tracks.isNotEmpty)
                Entrance(index: 2, child: _Recent(tracks: tracks)),
              Entrance(index: 3, child: const MoodSection()),
              if (source == MusicSource.youtube)
                Entrance(index: 3, child: _Stations(tracks: tracks)),
              if (source == MusicSource.youtube)
                Entrance(index: 4, child: _Discoveries(tracks: tracks)),
              const SizedBox(height: 32),
            ],
          ),
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

class _TrendingSection extends ConsumerWidget {
  const _TrendingSection({
    required this.provider,
    required this.title,
    required this.subtitle,
  });

  final FutureProvider<List<Track>> provider;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(provider);

    return trending.when(
      loading: () => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Загружаем музыку...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => _LoadFailed(onRetry: () => ref.invalidate(provider)),
      data: (items) {
        if (items.isEmpty) {
          return _LoadFailed(onRetry: () => ref.invalidate(provider));
        }
        final limited = items.take(12).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: title,
              subtitle: subtitle,
              action: TextButton(
                onPressed: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(limited.first, contextQueue: limited),
                child: const Text('Слушать'),
              ),
            ),
            _HorizontalRail(
              height: 190,
              itemCount: limited.length,
              itemBuilder: (context, i) {
                final track = limited[i];
                return SizedBox(
                  width: 136,
                  child: _TrackCard(
                    index: i,
                    track: track,
                    size: 136,
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTrack(track, contextQueue: limited),
                    onLongPress: () async {
                      await ref.read(libraryProvider).saveTrack(track);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Трек добавлен в медиатеку'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Удерживайте трек, чтобы сохранить его в медиатеку',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Карточка «подключите источник»: показывается, когда для источника нужен
/// личный токен, а он ещё не введён.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({
    required this.title,
    required this.message,
    required this.onTap,
  });

  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onTap, child: const Text('Открыть настройки')),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Не удалось загрузить музыку',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
            IconButton(
              tooltip: 'Диагностика сети',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NetworkDiagnosticsScreen(),
                ),
              ),
              icon: Icon(Icons.network_check_rounded,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Вставка ссылки на плейлист/альбом Spotify.
class _SpotifyLinkField extends ConsumerStatefulWidget {
  const _SpotifyLinkField();

  @override
  ConsumerState<_SpotifyLinkField> createState() => _SpotifyLinkFieldState();
}

class _SpotifyLinkFieldState extends ConsumerState<_SpotifyLinkField> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final text = _controller.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final link = parseSpotifyLink(text);
    if (link == null || link.kind == SpotifyKind.track) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Вставьте ссылку на плейлист или альбом Spotify')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final playlist = await ref.read(musicRepositoryProvider).spotifyPlaylist(text);
      if (!mounted || playlist == null || playlist.tracks.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Не удалось открыть подборку')),
        );
        return;
      }
      _controller.clear();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => PlaylistScreen(
            id: 'sp:${playlist.id}',
            title: playlist.title,
            subtitle: 'Spotify · ${playlist.tracks.length} треков',
            tracks: playlist.tracks,
            coverUrl: playlist.imageUrl,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось открыть подборку')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _controller,
        onSubmitted: (_) => _open(),
        textInputAction: TextInputAction.go,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Ссылка на плейлист или альбом Spotify',
          prefixIcon: const Icon(Icons.link_rounded, size: 20),
          suffixIcon: _busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  onPressed: _open,
                ),
        ),
      ),
    );
  }
}

/// Горизонтальная лента с «мягкими» краями прокрутки.
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
                  url: track.thumbnailUrl,
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

class _DailyPick extends StatelessWidget {
  const _DailyPick({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final lead = tracks.first;
    final artists = tracks.map((t) => t.artist).toSet().take(3).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'Подборка дня',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                  height: 1.1,
                ),
              ),
              SizedBox(width: 8),
              _LiveDot(),
            ],
          ),
          const SizedBox(height: 14),
          PressScale(
            scale: 0.975,
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
              borderRadius: BorderRadius.circular(22),
              child: AspectRatio(
                aspectRatio: 2.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverArt(
                      url: lead.thumbnailUrl,
                      path: lead.artworkPath,
                      size: 480,
                      radius: 0,
                      animate: false,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(gradient: AppColors.coverScrim),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'ТВОЙ\nМИКС',
                            style: TextStyle(
                              color: AppColors.accentSoft,
                              fontSize: 34,
                              height: 0.9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  artists,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.textPrimary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 26,
                                ),
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
          ),
        ],
      ),
    );
  }
}

/// Пульсирующая точка «в эфире».
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: TweenSequence<double>([
        TweenSequenceItem(tween: Tween<double>(begin: 0.35, end: 1), weight: 50),
        TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0.35), weight: 50),
      ]).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
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
          height: 156,
          child: ListView.separated(
            key: ValueKey(_revision),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recent.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final track = recent[i];
              final plays = settings.playCounts[track.id] ?? 0;
              return SizedBox(
                width: 108,
                child: _TrackCard(
                  index: i,
                  track: track,
                  subtitleOverride: plays > 1
                      ? '${track.artist} · $plays раз'
                      : null,
                  size: 108,
                  onTap: () => ref
                      .read(audioHandlerProvider)
                      .playTrack(track, contextQueue: recent),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Группирует треки по первому исполнителю, сохраняя порядок появления.
Map<String, List<Track>> _artistGroups(List<Track> tracks) =>
    groupTracksByArtist(tracks);

class _Stations extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = _artistGroups(tracks).entries.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Рекомендуемые станции',
          action: groups.isEmpty
              ? null
              : TextButton(
                  onPressed: () {
                    final all = [...tracks]..shuffle();
                    if (all.isEmpty) return;
                    ref
                        .read(audioHandlerProvider)
                        .playTrack(all.first, contextQueue: all);
                  },
                  child: const Text('Слушать'),
                ),
        ),
        SizedBox(
          height: 168,
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    'Добавьте треки — появятся станции по артистам',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final name = groups[i].key;
                    final own = groups[i].value;
                    // Станция артиста: его треки первыми, остальное — вперемешку.
                    final station = buildArtistMix(own, tracks);
                    return Entrance(
                      index: i,
                      child: StationCard(
                        title: name,
                        background: _palette[i % _palette.length],
                        centerUrl:
                            own.isNotEmpty ? own.first.thumbnailUrl : null,
                        leftUrl:
                            station.length > 1 ? station[1].thumbnailUrl : null,
                        rightUrl:
                            station.length > 2 ? station[2].thumbnailUrl : null,
                        size: 168,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistScreen(
                              id: 'station:$name',
                              title: '$name: радио',
                              isRadio: true,
                              tracks: station,
                            ),
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

class _Discoveries extends ConsumerWidget {
  const _Discoveries({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 44, 24, 0),
        child: Text(
          'Медиатека пуста.\nИмпортируйте аудио во вкладке «Создать»\nили найдите музыку в «Поиске».',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, height: 1.6),
        ),
      );
    }

    final groups = _artistGroups(tracks).entries.toList();
    final items = groups.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Ещё больше открытий',
          avatarUrl: items.first.value.first.thumbnailUrl,
        ),
        _HorizontalRail(
          height: 190,
          itemCount: items.length,
          itemBuilder: (context, i) {
            final name = items[i].key;
            final own = items[i].value;
            final lead = own.first;
            final mix = buildArtistMix(own, tracks, limit: 20);
            return SizedBox(
              width: 136,
              child: _TrackCard(
                index: i,
                track: lead,
                titleOverride: name,
                subtitleOverride:
                    own.length == 1 ? '1 трек' : '${own.length} треков',
                size: 136,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistScreen(
                      id: 'mix:$name',
                      title: '$name: микст',
                      subtitle: '${mix.length} треков',
                      tracks: mix,
                    ),
                  ),
                ),
                onLongPress: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(lead, contextQueue: mix),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Text(
            _summary(tracks),
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
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
