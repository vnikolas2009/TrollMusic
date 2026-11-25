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

/// Результат поиска по медиатеке.
class LibrarySearchResult {
  const LibrarySearchResult({
    this.tracks = const [],
    this.artists = const [],
    this.lyricMatches = const {},
  });

  /// Совпадения по названию, исполнителю или альбому.
  final List<Track> tracks;

  /// Исполнители, чьё имя содержит запрос.
  final List<String> artists;

  /// Треки, в чьём тексте найден запрос, и короткий фрагмент вокруг него.
  final Map<Track, String> lyricMatches;

  bool get isEmpty => tracks.isEmpty && artists.isEmpty && lyricMatches.isEmpty;
}

final RegExp _lrcTags = RegExp(r'\[[^\]]*\]|<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');

/// Фрагмент текста вокруг первого совпадения [needle] (без LRC-меток).
/// `null`, если совпадения нет.
String? lyricSnippet(String lyrics, String needle, {int radius = 36}) {
  final clean = lyrics
      .replaceAll(_lrcTags, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final at = clean.toLowerCase().indexOf(needle.toLowerCase());
  if (at < 0) return null;
  final start = (at - radius).clamp(0, clean.length);
  final end = (at + needle.length + radius).clamp(0, clean.length);
  return '${start > 0 ? '…' : ''}${clean.substring(start, end).trim()}${end < clean.length ? '…' : ''}';
}

/// Поиск по медиатеке: теги, исполнители и тексты песен.
/// [lyricsOf] возвращает сырой текст трека или `null`.
LibrarySearchResult searchLibrary(
  List<Track> all,
  String query,
  String? Function(String trackId) lyricsOf,
) {
  final needle = query.trim();
  if (needle.isEmpty) return const LibrarySearchResult();

  final byMeta = filterTracks(all, needle);
  final metaIds = byMeta.map((t) => t.id).toSet();

  final lower = needle.toLowerCase();
  final artists = <String>{
    for (final track in all)
      for (final name in track.artist.split(RegExp(r'[,&]')))
        if (name.trim().toLowerCase().contains(lower)) name.trim(),
  }.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final lyricMatches = <Track, String>{};
  // По тексту ищем от трёх символов, чтобы не получать шум.
  if (needle.length >= 3) {
    for (final track in all) {
      if (metaIds.contains(track.id)) continue;
      final raw = lyricsOf(track.id);
      if (raw == null) continue;
      final snippet = lyricSnippet(raw, needle);
      if (snippet != null) lyricMatches[track] = snippet;
    }
  }

  return LibrarySearchResult(
    tracks: byMeta,
    artists: artists,
    lyricMatches: lyricMatches,
  );
}
