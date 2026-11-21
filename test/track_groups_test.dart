import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/utils/track_groups.dart';
import 'package:trollmusic/data/models/track.dart';

Track _track(String id, String artist) => Track(
      id: id,
      title: 'Track $id',
      artist: artist,
      album: '',
      duration: const Duration(minutes: 3),
    );

void main() {
  group('groupTracksByArtist', () {
    test('groups by first artist and keeps order', () {
      final groups = groupTracksByArtist([
        _track('1', 'A'),
        _track('2', 'B, C'),
        _track('3', 'A'),
      ]);

      expect(groups.keys.toList(), ['A', 'B']);
      expect(groups['A']!.map((t) => t.id), ['1', '3']);
      expect(groups['B']!.map((t) => t.id), ['2']);
    });

    test('blank artist falls back to placeholder', () {
      final groups = groupTracksByArtist([_track('1', '  ')]);
      expect(groups.keys.single, 'Неизвестный исполнитель');
    });
  });

  group('buildArtistMix', () {    test('own tracks first and limit respected', () {
      final own = [_track('a1', 'A'), _track('a2', 'A')];
      final library = [
        ...own,
        _track('b1', 'B'),
        _track('b2', 'B'),
        _track('c1', 'C'),
      ];

      final mix = buildArtistMix(own, library, limit: 4);

      expect(mix.length, 4);
      expect(mix[0].id, 'a1');
      expect(mix[1].id, 'a2');
      expect(mix.skip(2).every((t) => t.artist != 'A'), isTrue);
    });

    test('no duplicates of own tracks in mix', () {
      final own = [_track('a1', 'A')];
      final library = [...own, _track('b1', 'B')];

      final mix = buildArtistMix(own, library);
      expect(mix.map((t) => t.id).toSet().length, mix.length);
    });
  });

  group('buildDailyPick', () {    test('is stable for the same date', () {
      final tracks = List.generate(20, (i) => _track('$i', 'A'));
      final date = DateTime(2026, 5, 4);

      final first = buildDailyPick(tracks, const [], date: date).map((t) => t.id).toList();
      final second = buildDailyPick(tracks, const [], date: date).map((t) => t.id).toList();

      expect(first, second);
      expect(first.length, 12);
    });

    test('changes across dates', () {
      final tracks = List.generate(20, (i) => _track('$i', 'A'));

      final a = buildDailyPick(tracks, const [], date: DateTime(2026, 5, 4));
      final b = buildDailyPick(tracks, const [], date: DateTime(2026, 5, 5));

      expect(a.map((t) => t.id).toList(), isNot(b.map((t) => t.id).toList()));
    });

    test('recent tracks go to the end', () {
      final tracks = List.generate(12, (i) => _track('$i', 'A'));
      final recent = tracks.take(3).map((t) => t.id).toList();

      final pick = buildDailyPick(tracks, recent, date: DateTime(2026, 5, 4));
      expect(pick, hasLength(12));
      expect(recent.any((id) => pick.take(9).any((t) => t.id == id)), isFalse);
    });

    test('empty library returns empty', () {
      expect(buildDailyPick(const [], const []), isEmpty);
    });
  });

  group('tracksByArtist', () {
    test('matches exact artist case-insensitively', () {
      final tracks = [
        _track('1', 'M83'),
        _track('2', 'M83, Susanne Sundfør'),
        _track('3', 'Kavinsky'),
      ];

      final own = tracksByArtist(tracks, 'm83');
      expect(own.map((t) => t.id), ['1', '2']);
    });

    test('does not match partial names', () {
      final tracks = [_track('1', 'M83')];
      expect(tracksByArtist(tracks, 'M8'), isEmpty);
    });

    test('empty name returns empty', () {
      final tracks = [_track('1', 'M83')];
      expect(tracksByArtist(tracks, '  '), isEmpty);
    });
  });
}
