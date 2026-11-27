import 'dart:math';

import '../../data/models/track.dart';

/// Вес трека при умном перемешивании: чем выше, тем раньше он окажется
/// в списке. [recentRank] — место в истории (0 — только что играл,
/// `null` — давно не играл), [playCount] — сколько раз трек слушали.
double shuffleWeight({int? recentRank, int playCount = 0}) {
  final recency = switch (recentRank) {
    null => 1.0,
    < 10 => 0.15,
    < 30 => 0.4,
    _ => 0.75,
  };
  // Редко слушаемые треки получают небольшой бонус.
  final novelty = 1 + 1 / (1 + playCount);
  return recency * novelty;
}

/// Перемешивание с учётом истории: недавно игравшие треки уходят ближе
/// к концу, редко слушаемые чаще оказываются впереди, а треки одного
/// исполнителя по возможности не стоят подряд.
List<Track> smartShuffle(
  List<Track> tracks, {
  required List<String> recentIds,
  required Map<String, int> playCounts,
  Random? random,
}) {
  final rng = random ?? Random();
  final rank = {for (var i = 0; i < recentIds.length; i++) recentIds[i]: i};

  // Взвешенная выборка без возвращения (Efraimidis–Spirakis).
  final keyed = [
    for (final t in tracks)
      (
        track: t,
        key: pow(
          1 - rng.nextDouble(),
          1 / shuffleWeight(recentRank: rank[t.id], playCount: playCounts[t.id] ?? 0),
        ).toDouble(),
      ),
  ]..sort((a, b) => b.key.compareTo(a.key));

  final list = [for (final k in keyed) k.track];
  return _spreadArtists(list);
}

String _artistKey(Track t) => t.artist.trim().toLowerCase();

/// Разводит соседние треки одного исполнителя, не меняя остальной порядок:
/// ближайший трек другого исполнителя переставляется на место конфликта.
List<Track> _spreadArtists(List<Track> list) {
  final out = [...list];
  for (var i = 1; i < out.length; i++) {
    final artist = _artistKey(out[i]);
    if (artist.isEmpty || artist != _artistKey(out[i - 1])) continue;

    final next = out.indexWhere(
      (t) => _artistKey(t) != artist,
      i + 1,
    );
    if (next < 0) break; // остались только треки этого исполнителя
    final moved = out.removeAt(next);
    out.insert(i, moved);
  }
  return out;
}
