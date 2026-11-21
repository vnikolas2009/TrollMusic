import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/track_search.dart';
import 'package:trollmusic/data/models/track.dart';

Track _track(String id, String title, String artist, {String album = ''}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: const Duration(minutes: 3),
    );

void main() {
  final library = [
    _track('1', 'Midnight City', 'M83', album: 'Hurry Up'),
    _track('2', 'Кино', 'Земфира', album: 'Прости меня'),
    _track('3', 'Nightcall', 'Kavinsky'),
  ];

  group('filterTracks', () {
    test('empty query returns everything', () {
      expect(filterTracks(library, ''), library);
      expect(filterTracks(library, '   '), library);
    });

    test('matches title case-insensitively', () {
      final result = filterTracks(library, 'midnight');
      expect(result.map((t) => t.id), ['1']);
    });

    test('matches artist', () {
      expect(filterTracks(library, 'kavinsky').map((t) => t.id), ['3']);
    });

    test('matches cyrillic artist', () {
      expect(filterTracks(library, 'земфира').map((t) => t.id), ['2']);
    });

    test('matches album', () {
      expect(filterTracks(library, 'hurry').map((t) => t.id), ['1']);
    });

    test('all words must match', () {
      final result = filterTracks(library, 'night kav');
      expect(result.map((t) => t.id), ['3']);
      expect(filterTracks(library, 'night земфира'), isEmpty);
    });

    test('no match returns empty list', () {
      expect(filterTracks(library, 'zzz'), isEmpty);
    });
  });
}
