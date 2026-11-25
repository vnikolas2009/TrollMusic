import '../../data/models/track.dart';

/// Порядок сортировки медиатеки.
enum TrackSort {
  recent('Недавно добавленные'),
  title('По названию'),
  artist('По исполнителю'),
  album('По альбому'),
  duration('По длительности'),
  mostPlayed('Часто слушаемые');

  const TrackSort(this.label);
  final String label;

  static TrackSort fromIndex(int index) =>
      index >= 0 && index < values.length ? values[index] : TrackSort.recent;
}

int _text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Возвращает отсортированную копию списка. [playCounts] нужен только для
/// [TrackSort.mostPlayed]. Порядок при равенстве стабилен (по названию).
List<Track> sortTracks(
  List<Track> tracks,
  TrackSort sort, {
  Map<String, int> playCounts = const {},
}) {
  final list = [...tracks];
  int byTitle(Track a, Track b) => _text(a.title, b.title);

  switch (sort) {
    case TrackSort.recent:
      list.sort((a, b) {
        final c = (b.addedAtMs ?? 0).compareTo(a.addedAtMs ?? 0);
        return c != 0 ? c : byTitle(a, b);
      });
    case TrackSort.title:
      list.sort(byTitle);
    case TrackSort.artist:
      list.sort((a, b) {
        final c = _text(a.artist, b.artist);
        return c != 0 ? c : byTitle(a, b);
      });
    case TrackSort.album:
      list.sort((a, b) {
        final c = _text(a.album, b.album);
        return c != 0 ? c : byTitle(a, b);
      });
    case TrackSort.duration:
      list.sort((a, b) {
        final c = b.duration.compareTo(a.duration);
        return c != 0 ? c : byTitle(a, b);
      });
    case TrackSort.mostPlayed:
      list.sort((a, b) {
        final c = (playCounts[b.id] ?? 0).compareTo(playCounts[a.id] ?? 0);
        return c != 0 ? c : byTitle(a, b);
      });
  }
  return list;
}

/// Группирует треки по альбому. Треки без альбома не попадают в результат.
Map<String, List<Track>> groupTracksByAlbum(List<Track> tracks) {
  final groups = <String, List<Track>>{};
  for (final track in tracks) {
    final album = track.album.trim();
    if (album.isEmpty) continue;
    groups.putIfAbsent(album, () => <Track>[]).add(track);
  }
  return groups;
}
