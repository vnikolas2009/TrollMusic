import 'package:flutter_test/flutter_test.dart';

import 'package:trollmusic/core/network/lyrics/lyrics_providers.dart';
import 'package:trollmusic/core/utils/lyrics_match.dart';

void main() {
  group('cleaning', () {
    test('cleanTitle strips track number, brackets, feat and remaster tails', () {
      expect(cleanTitle('01. Song Name (feat. Guest) [Explicit]'), 'Song Name');
      expect(cleanTitle('Song Name - Remastered 2011'), 'Song Name');
      expect(cleanTitle('Song_Name'), 'Song Name');
      expect(cleanTitle('Song Name feat. Someone'), 'Song Name');
    });

    test('primaryArtist takes the first of several', () {
      expect(primaryArtist('Artist A, Artist B'), 'Artist A');
      expect(primaryArtist('Artist A & Artist B'), 'Artist A');
      expect(primaryArtist('Artist A feat. B'), 'Artist A');
    });

    test('splitArtistFromTitle uses "Artist - Title" when tag is missing', () {
      final r = splitArtistFromTitle('Queen - Bohemian Rhapsody', '');
      expect(r.artist, 'Queen');
      expect(r.title, 'Bohemian Rhapsody');

      final kept = splitArtistFromTitle('Title', 'Real Artist');
      expect(kept.artist, 'Real Artist');
      expect(kept.title, 'Title');
    });

    test('splitArtistFromTitle also handles the unknown-artist label', () {
      final r = splitArtistFromTitle('02 - Band - Track', 'Неизвестный исполнитель');
      expect(r.artist, 'Band');
      expect(r.title, 'Track');
    });
  });

  group('buildQueries', () {
    test('goes from specific to broad without duplicates', () {
      final queries = buildQueries(
        title: 'Song (Live)',
        artist: 'Band feat. Guest',
        album: 'Album',
        durationSec: 200,
      );
      expect(queries.first.title, 'Song');
      expect(queries.first.artist, 'Band');
      expect(queries.first.durationSec, 200);
      expect(queries.last.artist, '');
      final keys = queries.map((q) => '${q.title}|${q.artist}|${q.album}|${q.durationSec}');
      expect(keys.toSet().length, queries.length);
    });

    test('unknown artist gives title-only query', () {
      final queries = buildQueries(title: 'Just Title', artist: 'Неизвестный исполнитель');
      expect(queries.every((q) => q.artist.isEmpty), isTrue);
    });
  });

  group('scoring', () {
    const query = LyricsQuery(title: 'Song', artist: 'Band', durationSec: 200);

    test('rejects wrong titles and far-off durations', () {
      expect(
        scoreCandidate(query, const LyricsCandidate(
          title: 'Another', artist: 'Band', source: 'x', plain: 'text')),
        isNull,
      );
      expect(
        scoreCandidate(query, const LyricsCandidate(
          title: 'Song', artist: 'Band', durationSec: 260, source: 'x', plain: 'text')),
        isNull,
      );
    });

    test('prefers synced and word-synced over plain', () {
      const plain = LyricsCandidate(
        title: 'Song', artist: 'Band', durationSec: 200, source: 'a', plain: 'text');
      const synced = LyricsCandidate(
        title: 'Song', artist: 'Band', durationSec: 200, source: 'b',
        synced: '[00:01.00]text');
      const words = LyricsCandidate(
        title: 'Song', artist: 'Band', durationSec: 200, source: 'c',
        synced: '[00:01.00]<00:01.00>text');
      expect(pickBest(query, [plain, synced, words])?.source, 'c');
      expect(pickBest(query, [plain, synced])?.source, 'b');
      expect(pickBest(query, [plain])?.source, 'a');
    });

    test('closer duration wins', () {
      const near = LyricsCandidate(
        title: 'Song', artist: 'Band', durationSec: 201, source: 'near',
        synced: '[00:01.00]x');
      const far = LyricsCandidate(
        title: 'Song', artist: 'Band', durationSec: 210, source: 'far',
        synced: '[00:01.00]x');
      expect(pickBest(query, [far, near])?.source, 'near');
    });

    test('candidate without any text is ignored', () {
      expect(
        pickBest(query, const [LyricsCandidate(title: 'Song', artist: 'Band', source: 'x')]),
        isNull,
      );
    });
  });

  group('lyricsFileMatchesTrack', () {
    test('matches by audio file name, title, and "artist - title"', () {
      expect(lyricsFileMatchesTrack(
        lyricsFileName: 'my_file', title: 'X', artist: 'Y', audioFileName: 'my_file'), isTrue);
      expect(lyricsFileMatchesTrack(
        lyricsFileName: 'Bohemian Rhapsody', title: 'Bohemian Rhapsody', artist: 'Queen'), isTrue);
      expect(lyricsFileMatchesTrack(
        lyricsFileName: 'Queen - Bohemian Rhapsody', title: 'Bohemian Rhapsody', artist: 'Queen'), isTrue);
    });

    test('does not match a different artist or title', () {
      expect(lyricsFileMatchesTrack(
        lyricsFileName: 'Other - Bohemian Rhapsody', title: 'Bohemian Rhapsody', artist: 'Queen'), isFalse);
      expect(lyricsFileMatchesTrack(
        lyricsFileName: 'Something', title: 'Bohemian Rhapsody', artist: 'Queen'), isFalse);
    });
  });
}
