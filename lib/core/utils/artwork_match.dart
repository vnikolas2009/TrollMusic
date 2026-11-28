/// Вариант обложки из поиска в интернете.
class ArtworkCandidate {
  const ArtworkCandidate({
    required this.title,
    required this.artist,
    required this.url,
  });

  final String title;
  final String artist;
  final String url;
}

/// Слова для сравнения: без регистра, скобок («feat.», «Remastered»),
/// знаков препинания.
List<String> artworkTokens(String value) {
  final cleaned = value
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
  if (cleaned.isEmpty) return const [];
  return cleaned.split(RegExp(r'\s+'));
}

bool _isUnknownArtist(String artist) {
  final a = artist.trim().toLowerCase();
  return a.isEmpty || a == 'unknown' || a == 'неизвестный исполнитель';
}

/// Доля слов [needle], встречающихся в [haystack].
double _coverage(List<String> needle, List<String> haystack) {
  if (needle.isEmpty) return 0;
  final set = haystack.toSet();
  return needle.where(set.contains).length / needle.length;
}

/// Лучший вариант обложки для трека или `null`, если уверенного совпадения
/// нет (лучше без обложки, чем с чужой). Название должно совпасть почти
/// полностью, исполнитель (если известен) — хотя бы наполовину.
ArtworkCandidate? pickBestArtwork(
  Iterable<ArtworkCandidate> candidates, {
  required String title,
  required String artist,
}) {
  final wantTitle = artworkTokens(title);
  if (wantTitle.isEmpty) return null;
  final checkArtist = !_isUnknownArtist(artist);
  final wantArtist = artworkTokens(artist);

  ArtworkCandidate? best;
  var bestScore = 0.0;
  for (final c in candidates) {
    if (c.url.isEmpty) continue;
    final titleScore = _coverage(wantTitle, artworkTokens(c.title));
    if (titleScore < 0.8) continue;

    var artistScore = 1.0;
    if (checkArtist && wantArtist.isNotEmpty) {
      artistScore = _coverage(wantArtist, artworkTokens(c.artist));
      if (artistScore < 0.5) continue;
    }

    final score = titleScore + artistScore;
    // при равенстве остаётся более ранний (поиск уже отсортирован по
    // релевантности)
    if (score > bestScore) {
      best = c;
      bestScore = score;
    }
  }
  return best;
}
