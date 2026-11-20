import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/network_providers.dart';
import '../../app/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
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
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Начните вводить название трека или имя артиста',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in queries)
                  ActionChip(
                    label: Text(query, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.surfaceAlt,
                    side: const BorderSide(color: AppColors.surfaceHigh),
                    onPressed: () => onPick(query),
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
  Timer? _debounce;
  List<Track> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
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
      final results = await ref.read(musicRepositoryProvider).searchYouTube(trimmed);
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
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background,
          title: const Text('Поиск'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Треки, артисты, подкасты',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Найдено: ${_results.length}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ref
                        .read(audioHandlerProvider)
                        .playTrack(_results.first, contextQueue: _results),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Слушать все'),
                  ),
                  IconButton(
                    tooltip: 'Сохранить в медиатеку',
                    onPressed: _saveResults,
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final track = _results[i];
              return TrackTile(
                title: track.title,
                artist: track.artist,
                coverUrl: track.thumbnailUrl,
                explicit: track.explicit,
                onTap: () => ref
                    .read(audioHandlerProvider)
                    .playTrack(track, contextQueue: _results),
                onMenu: () => _open(track),
              );
            },
          ),          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }

  void _saveResults() async {
    if (_results.isEmpty) return;
    final library = ref.read(libraryProvider);
    final query = _controller.text.trim();
    final title = query.isEmpty ? 'Поиск' : query;
    final now = DateTime.now();
    await library.savePlaylist(
      Playlist(
        id: 'search:${now.millisecondsSinceEpoch}',
        title: title,
        description: 'Результаты поиска',
        imageUrl: _results.first.thumbnailUrl,
        tracks: _results,
      ),
    );
    await library.saveTracks(_results);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранено: ${_results.length} треков')),
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
