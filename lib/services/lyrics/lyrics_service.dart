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

/// Лучший кандидат: сначала по ярусу, затем по оценке совпадения.
({LyricsCandidate candidate, int tier, double score})? pickByTier(
  LyricsQuery query,
  Iterable<LyricsCandidate> candidates,
) {
  ({LyricsCandidate candidate, int tier, double score})? best;
  for (final c in candidates) {
    final score = scoreCandidate(query, c);
    if (score == null) continue;
    final tier = lyricsTier(c);
    if (best == null ||
        tier > best.tier ||
        (tier == best.tier && score > best.score)) {
      best = (candidate: c, tier: tier, score: score);
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
              NeteaseProvider(),
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

      final found = _toFound(best.candidate);
      // Построчный или пословный текст — это уже хороший результат.
      if (best.tier >= 2) return found;
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

  LyricsFound _toFound(LyricsCandidate c) {
    if (c.hasSynced) {
      return LyricsFound(
        text: c.synced!.trim(),
        synced: true,
        wordSynced: LrcParser.hasWordTiming(c.synced!),
        source: c.source,
      );
    }
    return LyricsFound(
      text: c.plain!.trim(),
      synced: false,
      wordSynced: false,
      source: c.source,
    );
  }
}
