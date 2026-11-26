import '../../core/network/lyrics/asia_providers.dart';
import '../../core/network/lyrics/lyrics_providers.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/lyrics_match.dart';

/// Найденный текст.
class LyricsFound {
  const LyricsFound({
    required this.text,
    required this.synced,
    required this.wordSynced,
    required this.source,
  });

  /// LRC (в том числе enhanced) или обычный текст.
  final String text;

  /// Есть таймкоды строк.
  final bool synced;

  /// Есть пословные метки (enhanced LRC).
  final bool wordSynced;

  /// Идентификатор источника.
  final String source;
}

/// Ярус текста: чем выше, тем лучше. Enhanced LRC всегда выигрывает у
/// обычного LRC, а тот — у текста без таймкодов.
int lyricsTier(LyricsCandidate c) {
  if (c.hasSynced) return LrcParser.hasWordTiming(c.synced!) ? 3 : 2;
  return c.hasPlain ? 1 : 0;
}

/// Оценка кандидата для выбора, больше — лучше.
///
/// Основа — ярус [lyricsTier]. Поправки:
/// - таймкоды не подходят по длительности ([timingMismatch]): текст всё ещё
///   полезен, но показывается без таймкодов, поэтому ярус 1;
/// - часть слов замазана ([looksCensored]): не выше яруса 2 и минус 0,5,
///   чтобы полный текст из другого источника выигрывал при равных таймкодах.
double lyricsRank(LyricsQuery query, LyricsCandidate c) {
  var rank = lyricsTier(c).toDouble();
  if (rank >= 2 && timingMismatch(query, c)) rank = 1;
  if (looksCensored(c.synced ?? c.plain ?? '')) {
    rank = (rank > 2 ? 2 : rank) - 0.5;
  }
  return rank;
}

/// Лучший кандидат: сначала по [lyricsRank], затем по оценке совпадения.
/// `tier` — исходный ярус текста, `rank` — с учётом поправок,
/// `degraded` — таймкоды неточны, текст нужно отдать без них.
({
  LyricsCandidate candidate,
  int tier,
  double rank,
  bool degraded,
  double score,
})? pickByTier(
  LyricsQuery query,
  Iterable<LyricsCandidate> candidates,
) {
  ({
    LyricsCandidate candidate,
    int tier,
    double rank,
    bool degraded,
    double score,
  })? best;
  for (final c in candidates) {
    final score = scoreCandidate(query, c);
    if (score == null) continue;
    final tier = lyricsTier(c);
    final rank = lyricsRank(query, c);
    if (best == null ||
        rank > best.rank ||
        (rank == best.rank && score > best.score)) {
      best = (
        candidate: c,
        tier: tier,
        rank: rank,
        degraded: tier >= 2 && timingMismatch(query, c),
        score: score,
      );
    }
  }
  return best;
}

/// Ищет текст песни во всех источниках сразу. Приоритет: enhanced LRC,
/// затем LRC, затем обычный текст. Если по точному запросу ничего не нашлось,
/// пробуются более широкие варианты запроса.
class LyricsService {
  LyricsService({List<LyricsProvider>? providers})
      : providers = providers ??
            <LyricsProvider>[
              LrclibProvider(),
              KugouProvider(),
              QqMusicProvider(),
              LyricsOvhProvider(),
            ];

  final List<LyricsProvider> providers;

  static const _maxQueries = 3;
  static const _providerTimeout = Duration(seconds: 15);

  Future<LyricsFound?> find({
    required String title,
    required String artist,
    String album = '',
    int durationSec = 0,
    String? onlyProvider,
  }) async {
    final queries = buildQueries(
      title: title,
      artist: artist,
      album: album,
      durationSec: durationSec,
    ).take(_maxQueries).toList();
    if (queries.isEmpty) return null;

    final active = onlyProvider == null
        ? providers
        : providers.where((p) => p.id == onlyProvider).toList();

    LyricsFound? fallback;

    for (final query in queries) {
      final results = await Future.wait(active.map((p) => _safe(p, query)));

      final pool = <LyricsCandidate>[for (final r in results) ...r];
      final best = pickByTier(query, pool);
      if (best == null) continue;

      final found = _toFound(best.candidate, degraded: best.degraded);
      // Построчный или пословный текст с точными таймкодами и без замазанных
      // слов — это уже хороший результат.
      if (best.rank >= 2) return found;
      fallback ??= found;
    }
    return fallback;
  }

  Future<List<LyricsCandidate>> _safe(
    LyricsProvider provider,
    LyricsQuery query,
  ) async {
    try {
      return await provider.search(query).timeout(_providerTimeout);
    } catch (_) {
      return const [];
    }
  }

  LyricsFound _toFound(LyricsCandidate c, {bool degraded = false}) {
    if (c.hasSynced && !degraded) {
      return LyricsFound(
        text: c.synced!.trim(),
        synced: true,
        wordSynced: LrcParser.hasWordTiming(c.synced!),
        source: c.source,
      );
    }
    // Неточные таймкоды хуже их отсутствия: отдаём только текст.
    final plain = c.hasPlain
        ? c.plain!.trim()
        : LrcParser.plainLines(c.synced!).join('\n');
    return LyricsFound(
      text: plain,
      synced: false,
      wordSynced: false,
      source: c.source,
    );
  }
}
