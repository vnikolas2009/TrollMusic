import '../../data/models/track.dart';

/// Одно прослушивание из журнала.
typedef PlayEvent = ({String trackId, DateTime at});

/// Запись журнала: `<миллисекунды с эпохи>:<id трека>`.
String encodePlayEvent(String trackId, DateTime at) =>
    '${at.millisecondsSinceEpoch}:$trackId';

List<PlayEvent> parsePlayLog(Iterable<String> rows) {
  final out = <PlayEvent>[];
  for (final row in rows) {
    final cut = row.indexOf(':');
    if (cut <= 0) continue;
    final ms = int.tryParse(row.substring(0, cut));
    final id = row.substring(cut + 1);
    if (ms == null || id.isEmpty) continue;
    out.add((trackId: id, at: DateTime.fromMillisecondsSinceEpoch(ms)));
  }
  return out;
}

class StatsSummary {
  const StatsSummary({
    required this.plays,
    required this.listened,
    required this.topTracks,
    required this.topArtists,
  });

  final int plays;

  /// Оценка: сумма длительностей прослушанных треков.
  final Duration listened;
  final List<({Track track, int plays})> topTracks;
  final List<({String artist, int plays})> topArtists;
}

/// Статистика за период: события раньше [since] отбрасываются, треки,
/// которых уже нет в медиатеке, пропускаются.
StatsSummary computeStats(
  Iterable<PlayEvent> events,
  Map<String, Track> tracks, {
  DateTime? since,
  int top = 5,
}) {
  final perTrack = <String, int>{};
  final perArtist = <String, int>{};
  var plays = 0;
  var listened = Duration.zero;

  for (final e in events) {
    if (since != null && e.at.isBefore(since)) continue;
    final track = tracks[e.trackId];
    if (track == null) continue;
    plays++;
    listened += track.duration;
    perTrack[e.trackId] = (perTrack[e.trackId] ?? 0) + 1;
    final artist = track.artist.trim().isEmpty ? 'Неизвестный исполнитель' : track.artist.trim();
    perArtist[artist] = (perArtist[artist] ?? 0) + 1;
  }

  int byCount(int a, int b) => b.compareTo(a);

  final topTracks = perTrack.entries.toList()
    ..sort((a, b) {
      final c = byCount(a.value, b.value);
      return c != 0 ? c : tracks[a.key]!.title.compareTo(tracks[b.key]!.title);
    });
  final topArtists = perArtist.entries.toList()
    ..sort((a, b) {
      final c = byCount(a.value, b.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });

  return StatsSummary(
    plays: plays,
    listened: listened,
    topTracks: [for (final e in topTracks.take(top)) (track: tracks[e.key]!, plays: e.value)],
    topArtists: [for (final e in topArtists.take(top)) (artist: e.key, plays: e.value)],
  );
}
