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

  /// Идентификатор источника (`lrclib`, `netease`, `ovh`).
  final String source;
}

/// Ищет текст песни в нескольких источниках. Приоритет у текстов с таймкодами,
/// затем с пословными метками; обычный текст берётся, если больше ничего нет.
class LyricsService {
  LyricsService({List<LyricsProvider>? providers})
      : providers = providers ??
            <LyricsProvider>[
              LrclibProvider(),
              NeteaseProvider(),
              LyricsOvhProvider(),
            ];

  final List<LyricsProvider> providers;

  /// Не больше стольких вариантов запроса на один источник.
  static const _maxQueries = 3;

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

    LyricsFound? plainFallback;

    for (final provider in active) {
      for (final query in queries) {
        List<LyricsCandidate> candidates;
        try {
          candidates = await provider.search(query);
        } catch (_) {
          continue;
        }
        final best = pickBest(query, candidates);
        if (best == null) continue;

        if (best.hasSynced) {
          return LyricsFound(
            text: best.synced!.trim(),
            synced: true,
            wordSynced: LrcParser.hasWordTiming(best.synced!),
            source: provider.id,
          );
        }
        plainFallback ??= LyricsFound(
          text: best.plain!.trim(),
          synced: false,
          wordSynced: false,
          source: provider.id,
        );
        break;
      }
    }
    return plainFallback;
  }
}
