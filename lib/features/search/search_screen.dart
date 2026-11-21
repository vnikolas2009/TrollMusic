import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/entrance.dart';
import '../../shared/widgets/pill_toggle.dart';
import '../../shared/widgets/track_tile.dart';
import '../playlist/playlist_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _RecentQueries extends StatelessWidget {
  const _RecentQueries({
    required this.queries,
    required this.onPick,
    required this.onClear,
  });

  final List<String> queries;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (queries.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 40, 32, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 36,
                color: AppColors.textTertiary,
              ),
              SizedBox(height: 14),
              Text(
                'Начните вводить название трека или имя артиста',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Недавние запросы',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: onClear,
                  child: const Text('Очистить'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < queries.length; i++)
                  Entrance(
                    index: i,
                    offsetY: 0.06,
                    child: ActionChip(
                      avatar: Icon(
                        Icons.north_west_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      label: Text(
                        queries[i],
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: AppColors.surfaceAlt,
                      side: BorderSide.none,
                      onPressed: () => onPick(queries[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<Track> _results = const [];
  bool _loading = false;
  String? _error;
  TrackSource? _source;
  bool _focused = false;

  List<Track> get _filtered => _source == null
      ? _results
      : _results.where((t) => t.source == _source).toList();

  List<({String label, TrackSource? source})> get _sourceFilters => [
        (label: 'Все', source: null),
        if (_results.any((t) => t.source == TrackSource.youtube))
          (label: 'YouTube', source: TrackSource.youtube),
        if (_results.any((t) => t.source == TrackSource.spotify))
          (label: 'Spotify', source: TrackSource.spotify),
      ];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (_focused == _focus.hasFocus) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Кнопка очистки появляется сразу, запрос — после паузы.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 420), () => _search(value));
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    ref.read(settingsProvider).rememberQuery(trimmed);
    if (mounted) setState(() {});
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(musicRepositoryProvider);
      final results = await repo.searchAll(trimmed);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось выполнить поиск. Проверьте зеркала в настройках.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filters = _sourceFilters;
    final filterIndex = filters.indexWhere((f) => f.source == _source);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background.withValues(alpha: 0.92),
          surfaceTintColor: Colors.transparent,
          title: const Text('Поиск'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.emphasized,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focused
                      ? AppColors.textPrimary.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: AppColors.accentTint,
                          blurRadius: 22,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Треки, артисты, подкасты',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _debounce?.cancel();
                            setState(() {
                              _results = const [];
                              _error = null;
                              _loading = false;
                            });
                            _focus.requestFocus();
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(36),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else if (_results.isEmpty)
          _RecentQueries(
            queries: ref.watch(settingsProvider).searchQueries,
            onPick: (query) {
              _controller.text = query;
              _search(query);
            },
            onClear: () {
              ref.read(settingsProvider).clearSearchQueries();
              setState(() {});
            },
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Найдено: ${_results.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _filtered.isEmpty
                        ? null
                        : () => ref
                            .read(audioHandlerProvider)
                            .playTrack(_filtered.first, contextQueue: _filtered),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Слушать все'),
                  ),
                  IconButton(
                    tooltip: 'Сохранить в медиатеку',
                    onPressed: _saveResults,
                    icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (filters.length > 2)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillToggle(
                    labels: [for (final f in filters) f.label],
                    index: filterIndex < 0 ? 0 : filterIndex,
                    onChanged: (i) =>
                        setState(() => _source = filters[i].source),
                  ),
                ),
              ),
            ),
          SliverList.builder(
            itemCount: _filtered.length,
            itemBuilder: (context, i) {
              final track = _filtered[i];
              return TrackTile(
                title: track.title,
                artist: track.artist,
                coverUrl: track.thumbnailUrl,
                explicit: track.explicit,
                index: i,
                onTap: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(track, contextQueue: _filtered),
                onMenu: () => _open(track),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ],
    );
  }

  void _saveResults() async {
    final tracks = _filtered;
    if (tracks.isEmpty) return;
    final library = ref.read(libraryProvider);
    final query = _controller.text.trim();
    final title = query.isEmpty ? 'Поиск' : query;
    final now = DateTime.now();
    await library.savePlaylist(
      Playlist(
        id: 'search:${now.millisecondsSinceEpoch}',
        title: title,
        description: 'Результаты поиска',
        imageUrl: tracks.first.thumbnailUrl,
        tracks: tracks,
      ),
    );
    await library.saveTracks(tracks);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранено: ${tracks.length} треков')),
    );
  }

  void _open(Track track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistScreen(
          id: 'search:${track.id}',
          title: track.title,
          subtitle: track.artist,
          tracks: [track],
        ),
      ),
    );
  }
}
