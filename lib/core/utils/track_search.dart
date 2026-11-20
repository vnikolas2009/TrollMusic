import '../../data/models/track.dart';

/// Фильтрует треки по подстроке в названии, исполнителе и альбоме.
/// Пустой запрос возвращает исходный список без изменений.
List<Track> filterTracks(List<Track> tracks, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return tracks;

  final words = needle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return tracks;

  return tracks.where((track) {
    final haystack = '${track.title} ${track.artist} ${track.album}'.toLowerCase();
    return words.every(haystack.contains);
  }).toList();
}
