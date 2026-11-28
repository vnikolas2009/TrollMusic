import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/utils/play_stats.dart';
import 'package:trollmusic/data/models/track.dart';

Track t(String id, String artist, {int sec = 200}) =>
    Track(id: id, title: id, artist: artist, duration: Duration(seconds: sec));

void main() {
  final tracks = {
    'a': t('a', 'X'),
    'b': t('b', 'X'),
    'c': t('c', 'Y', sec: 100),
  };
  final now = DateTime(2026, 11, 28);

  test('журнал кодируется и разбирается, мусор пропускается', () {
    final row = encodePlayEvent('a:1', now);
    final parsed = parsePlayLog([row, 'мусор', ':x', '12:']);
    expect(parsed.length, 1);
    expect(parsed.single.trackId, 'a:1');
    expect(parsed.single.at, now);
  });

  test('подсчёт, топ и время', () {
    final events = [
      (trackId: 'a', at: now),
      (trackId: 'a', at: now),
      (trackId: 'b', at: now),
      (trackId: 'c', at: now),
      (trackId: 'gone', at: now),
    ];
    final s = computeStats(events, tracks);
    expect(s.plays, 4);
    expect(s.listened, const Duration(seconds: 700));
    expect(s.topTracks.first.track.id, 'a');
    expect(s.topTracks.first.plays, 2);
    expect(s.topArtists.first.artist, 'X');
    expect(s.topArtists.first.plays, 3);
  });

  test('период отсекает старые события, top ограничивает список', () {
    final events = [
      (trackId: 'a', at: now.subtract(const Duration(days: 30))),
      (trackId: 'b', at: now),
      (trackId: 'c', at: now),
    ];
    final s = computeStats(events, tracks, since: now.subtract(const Duration(days: 7)), top: 1);
    expect(s.plays, 2);
    expect(s.topTracks.length, 1);
  });

  test('пустой журнал', () {
    final s = computeStats(const [], tracks);
    expect(s.plays, 0);
    expect(s.topTracks, isEmpty);
  });
}
