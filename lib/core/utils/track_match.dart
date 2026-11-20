import '../../data/models/track.dart';

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

final _variant = RegExp(r'\b(live|remix|cover|karaoke|instrumental|slowed|sped)\b');

/// Выбирает из результатов поиска YouTube лучшее совпадение для трека
/// (Spotify-трек не имеет videoId): близкая длительность, название и исполнитель.
Track? pickBestMatch(Track target, List<Track> candidates) {
  if (candidates.isEmpty) return null;
  final want = target.duration.inSeconds;
  final title = _norm(target.title);
  final artist = _norm(target.artist.split(',').first);
  final wantsVariant = _variant.hasMatch(title);

  Track? best;
  var bestScore = double.negativeInfinity;
  for (final c in candidates) {
    var score = 0.0;
    final have = c.duration.inSeconds;
    if (want > 0 && have > 0) {
      final diff = (have - want).abs();
      score -= diff > 10 ? 50 + diff.toDouble() : diff.toDouble();
    }
    final cTitle = _norm(c.title);
    if (title.isNotEmpty && cTitle.contains(title)) score += 20;
    if (artist.isNotEmpty && (_norm(c.artist).contains(artist) || cTitle.contains(artist))) {
      score += 10;
    }
    if (!wantsVariant && _variant.hasMatch(cTitle)) score -= 15;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best;
}
