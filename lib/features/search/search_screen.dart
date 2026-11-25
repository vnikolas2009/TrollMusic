import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/track_search.dart';
import '../../data/models/track.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';
import '../library/track_list_screen.dart';

/// Поиск по медиатеке: названия, исполнители, альбомы и тексты песен.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tracksProvider).value ?? const <Track>[];
    final library = ref.watch(libraryProvider);
    final settings = ref.read(settingsProvider);
    final audio = ref.read(audioHandlerProvider);
    final current = ref.watch(currentTrackProvider).value;

    final result = searchLibrary(all, _query, library.lyricsFor);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.appBarBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('Поиск'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (v) => settings.rememberQuery(v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Трек, исполнитель, альбом или строчка из песни',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _set(''),
                      ),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? _Recent(
                    queries: settings.searchQueries,
                    onPick: _set,
                    onClear: () => setState(settings.clearSearchQueries),
                  )
                : result.isEmpty
                    ? Center(
                        child: Text(
                          'Ничего не найдено',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          if (result.artists.isNotEmpty) ...[
                            const _Header('Исполнители'),
                            for (final name in result.artists.take(5))
                              ListTile(
                                leading: const Icon(Icons.person_rounded),
                                title: Text(name),
                                onTap: () {
                                  settings.rememberQuery(_query.trim());
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => TrackListScreen.artist(name: name),
                                  ));
                                },
                              ),
                          ],
                          if (result.tracks.isNotEmpty) ...[
                            const _Header('Треки'),
                            for (final track in result.tracks.take(50))
                              TrackTile(
                                title: track.title,
                                artist: track.artist,
                                coverPath: track.artworkPath,
                                active: current?.id == track.id,
                                hasLyrics: library.hasLyrics(track.id),
                                onTap: () {
                                  settings.rememberQuery(_query.trim());
                                  audio.playTrack(track, contextQueue: result.tracks);
                                },
                                onMenu: () => showTrackActions(context, ref, track),
                              ),
                          ],
                          if (result.lyricMatches.isNotEmpty) ...[
                            const _Header('В текстах песен'),
                            for (final entry in result.lyricMatches.entries.take(30))
                              ListTile(
                                leading: const Icon(Icons.lyrics_outlined),
                                title: Text(entry.key.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '${entry.key.artist} · ${entry.value}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => audio.playTrack(entry.key),
                              ),
                          ],
                          const SizedBox(height: 96),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
}

class _Recent extends StatelessWidget {
  const _Recent({
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Ищите по названию, исполнителю, альбому\nили по строчке из текста песни',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Недавние запросы',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onClear, child: const Text('Очистить')),
            ],
          ),
        ),
        for (final q in queries)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            onTap: () => onPick(q),
          ),
      ],
    );
  }
}
