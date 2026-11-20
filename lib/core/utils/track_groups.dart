import '../../data/models/track.dart';

/// Группирует треки по первому исполнителю, сохраняя порядок появления.
Map<String, List<Track>> groupTracksByArtist(List<Track> tracks) {
  final groups = <String, List<Track>>{};
  for (final track in tracks) {
    final name = track.artist.split(',').first.trim();
    final key = name.isEmpty ? 'Неизвестный исполнитель' : name;
    groups.putIfAbsent(key, () => <Track>[]).add(track);
  }
  return groups;
}

/// Собирает микс: треки исполнителя идут первыми, остальное — вперемешку.
List<Track> buildArtistMix(
  List<Track> own,
  List<Track> library, {
  int limit = 25,
}) {
  final rest = library.where((t) => !own.contains(t)).toList()..shuffle();
  return <Track>[...own, ...rest].take(limit).toList();
}

/// Все треки, где исполнитель указан в списке артистов трека.
/// Сравнение без учёта регистра и лишних пробелов.
List<Track> tracksByArtist(List<Track> tracks, String name) {
  final needle = name.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  return tracks.where((track) {
    final artists = track.artist
        .split(RegExp(r'[,&]'))
        .map((a) => a.trim().toLowerCase())
        .where((a) => a.isNotEmpty);
    return artists.contains(needle);
  }).toList();
}

/// Подборка дня: стабильна в течение суток, недавно слушанное — в конце.
List<Track> buildDailyPick(
  List<Track> tracks,
  List<String> recentIds, {
  DateTime? date,
  int limit = 12,
}) {
  if (tracks.isEmpty) return const [];
  final day = date ?? DateTime.now();
  final seed = day.year * 10000 + day.month * 100 + day.day;
  final recent = recentIds.take(5).toSet();

  final pool = [...tracks]
    ..sort((a, b) {
      final aRecent = recent.contains(a.id) ? 1 : 0;
      final bRecent = recent.contains(b.id) ? 1 : 0;
      if (aRecent != bRecent) return aRecent.compareTo(bRecent);
      return _stableHash(a.id, seed).compareTo(_stableHash(b.id, seed));
    });

  return pool.take(limit).toList();
}

int _stableHash(String id, int seed) {
  var hash = 2166136261 & 0x7fffffff;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
  }
  hash = ((hash ^ seed) * 16777619) & 0x7fffffff;
  hash ^= hash >> 13;
  hash = (hash * 1274126177) & 0x7fffffff;
  return hash ^ (hash >> 16);
}
