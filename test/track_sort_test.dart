import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/track_search.dart';
import 'package:trollmusic/core/utils/track_sort.dart';
import 'package:trollmusic/data/models/track.dart';

Track _t(String id, String title, String artist,
        {String album = '', int sec = 0, int? added}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: Duration(seconds: sec),
      addedAtMs: added,
    );

void main() {
  final tracks = [
    _t('1', 'Beta', 'Zed', album: 'B', sec: 100, added: 1),
    _t('2', 'alpha', 'Yan', album: 'A', sec: 300, added: 3),
    _t('3', 'Gamma', 'Xu', sec: 200, added: 2),
  ];

  List<String> ids(List<Track> l) => l.map((t) => t.id).toList();

  group('sortTracks', () {
    test('by title ignores case', () {
      expect(ids(sortTracks(tracks, TrackSort.title)), ['2', '1', '3']);
    });
    test('recent puts newest first', () {
      expect(ids(sortTracks(tracks, TrackSort.recent)), ['2', '3', '1']);
    });
    test('by artist, album and duration', () {
      expect(ids(sortTracks(tracks, TrackSort.artist)), ['3', '2', '1']);
      expect(ids(sortTracks(tracks, TrackSort.album)), ['3', '2', '1']);
      expect(ids(sortTracks(tracks, TrackSort.duration)), ['2', '3', '1']);
    });
    test('most played uses counts and falls back to title', () {
      final sorted = sortTracks(tracks, TrackSort.mostPlayed, playCounts: {'3': 5, '1': 5});
      expect(ids(sorted), ['1', '3', '2']);
    });
    test('does not mutate the input', () {
      sortTracks(tracks, TrackSort.title);
      expect(ids(tracks), ['1', '2', '3']);
    });
    test('fromIndex clamps unknown values', () {
      expect(TrackSort.fromIndex(99), TrackSort.recent);
      expect(TrackSort.fromIndex(1), TrackSort.title);
    });
  });

  test('groupTracksByAlbum skips tracks without album', () {
    final groups = groupTracksByAlbum(tracks);
    expect(groups.keys.toSet(), {'A', 'B'});
  });

  group('searchLibrary', () {
    String? lyrics(String id) => id == '3' ? '[00:01.00]<00:01.00>Dancing <00:02.00>in the moonlight' : null;

    test('finds by meta and artists', () {
      final r = searchLibrary(tracks, 'yan', lyrics);
      expect(ids(r.tracks), ['2']);
      expect(r.artists, ['Yan']);
    });

    test('finds a line inside lyrics and strips LRC tags from the snippet', () {
      final r = searchLibrary(tracks, 'moonlight', lyrics);
      expect(r.tracks, isEmpty);
      final entry = r.lyricMatches.entries.single;
      expect(entry.key.id, '3');
      expect(entry.value, contains('moonlight'));
      expect(entry.value, isNot(contains('<')));
      expect(entry.value, isNot(contains('[')));
    });

    test('short queries do not scan lyrics', () {
      expect(searchLibrary(tracks, 'mo', lyrics).lyricMatches, isEmpty);
    });

    test('empty query returns empty result', () {
      expect(searchLibrary(tracks, '  ', lyrics).isEmpty, isTrue);
    });
  });
}
