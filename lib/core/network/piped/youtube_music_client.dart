import 'dart:io';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../../utils/async_utils.dart';
import '../../utils/network_kind.dart';
import '../../utils/track_match.dart';
import '../proxy.dart';
import '../worker_health.dart';
import '../youtube/innertube_client.dart';
import '../youtube/stream_candidate.dart';
import 'invidious_client.dart';
import 'piped_client.dart';

/// Единая точка доступа к музыке YouTube Music без настройки со стороны пользователя.
///
/// Все источники (InnerTube, Piped, Invidious) опрашиваются параллельно,
/// побеждает самый быстрый ответ; недоступные зеркала временно «остывают».
class YouTubeMusicClient {
  YouTubeMusicClient({
    required PipedClient piped,
    required InvidiousClient invidious,
    required Settings settings,
    ProxyConfig? proxy,
    WorkerHealth? health,
  })  : _piped = piped,
        _invidious = invidious,
        _settings = settings,
        _proxy = proxy,
        _health = health,
        _innerTube = InnerTubeClient(settings: settings);

  final PipedClient _piped;
  final InvidiousClient _invidious;
  final Settings _settings;
  final ProxyConfig? _proxy;
  final WorkerHealth? _health;
  final InnerTubeClient _innerTube;

  static const _streamTtl = Duration(minutes: 25);

  final _streamCache = <String, ({DateTime at, List<StreamCandidate> list})>{};
  final _matched = <String, String>{};
  final _mixCache = <String, ({DateTime at, List<Track> tracks})>{};

  // ----------------------------------------------------------------- поиск

  Future<List<Track>> search(String query) async {
    // Сначала только песни YouTube Music (не видео), и лишь потом — запасные
    // источники, которые отдают обычные видео.
    try {
      final songs = await _innerTube
          .searchMusic(query)
          .timeout(const Duration(seconds: 6));
      if (songs.isNotEmpty) return songs;
    } catch (_) {}

    return firstNonEmptyList<Track>(
      [
        () => _piped.search(query),
        () => _invidious.search(query),
        () => _innerTube.search(query),
      ],
      timeout: const Duration(seconds: 9),
    );
  }

  /// Подборка музыки по нескольким запросам: результаты перемешиваются по кругу,
  /// дубликаты удаляются. Кэшируется на 30 минут.
  Future<List<Track>> mix(List<String> queries, {int limit = 30}) async {
    final key = '$limit|${queries.join('|')}';
    final cached = _mixCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 30)) {
      return cached.tracks;
    }

    final results = await Future.wait([
      for (final query in queries) _safeSearch(query),
    ]);

    final out = <Track>[];
    final seenIds = <String>{};
    final seenNames = <String>{};
    var round = 0;
    var added = true;
    while (out.length < limit && added) {
      added = false;
      for (final list in results) {
        if (round >= list.length || out.length >= limit) continue;
        final track = list[round];
        final name = '${track.artist}|${track.title}'.toLowerCase();
        if (seenIds.add(track.id) && seenNames.add(name)) {
          out.add(track);
          added = true;
        }
      }
      round++;
      if (round > 60) break;
    }

    if (out.isNotEmpty) {
      _mixCache[key] = (at: DateTime.now(), tracks: out);
    }
    return out;
  }

  Future<List<Track>> trendingMusic() =>
      mix(AppConfig.trendingQueries, limit: 30);

  Future<List<Track>> trending() => trendingMusic();

  Future<List<Track>> _safeSearch(String query) async {
    try {
      return await search(query);
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------------ потоки

  /// Основной резолвер для плеера: прямые ссылки с заголовками, под которые
  /// они выданы. Ссылки живут недолго, поэтому кэш — только 25 минут.
  ///
  /// [fresh] — повторная попытка после ошибки: кэш пропускается и опрашиваются
  /// все источники, чтобы получить ссылки от разных провайдеров.
  Future<List<StreamCandidate>> resolveCandidates(
    Track track, {
    bool fresh = false,
  }) async {
    final local = track.localPath;
    if (local != null && local.isNotEmpty) return const [];

    final videoId = await _videoIdFor(track);
    if (videoId == null) return const [];

    if (!fresh) {
      final hit = _streamCache[videoId];
      if (hit != null && DateTime.now().difference(hit.at) < _streamTtl) {
        return hit.list;
      }
    }

    final onWifi = await isOnWifi();
    final quality = _settings.audioQuality;
    final providers = <Future<List<StreamCandidate>> Function()>[
      () => _innerTube.audioStreams(
            videoId,
            quality: quality,
            onWifi: onWifi,
            aacOnly: Platform.isIOS,
          ),
      () => _pipedCandidates(videoId),
      () => _invidiousCandidates(videoId),
      () => _workerCandidates(videoId),
    ];

    List<StreamCandidate> list;
    if (fresh) {
      final all = await Future.wait([
        for (final provider in providers) _safeStreams(provider),
      ]).timeout(const Duration(seconds: 12), onTimeout: () => const []);
      final seen = <String>{};
      list = [
        for (final part in all)
          for (final candidate in part)
            if (seen.add(candidate.url)) candidate,
      ];
    } else {
      list = await firstNonEmptyList<StreamCandidate>(
        providers,
        timeout: const Duration(seconds: 14),
      );
    }

    if (list.isNotEmpty) {
      _streamCache[videoId] = (at: DateTime.now(), list: list);
    }
    return list;
  }

  Future<List<StreamCandidate>> _safeStreams(
    Future<List<StreamCandidate>> Function() provider,
  ) async {
    try {
      return await provider();
    } catch (_) {
      return const [];
    }
  }

  Future<List<StreamCandidate>> _pipedCandidates(String videoId) async {
    final urls = await _piped.resolveStreamUrls(videoId);
    return [
      for (final url in urls)
        StreamCandidate(url: url, userAgent: AppConfig.genericAudioUserAgent),
    ];
  }

  /// Встроенный Worker: сам резолвит трек и отдаёт байты (последний рубеж,
  /// когда прямые ссылки googlevideo недоступны у провайдера).
  Future<List<StreamCandidate>> _workerCandidates(String videoId) async {
    final proxy = _proxy;
    if (proxy == null || !proxy.hasWorker || !(_health?.usable ?? true)) {
      return const [];
    }
    return [
      StreamCandidate(
        url: proxy.stream(videoId).toString(),
        userAgent: AppConfig.genericAudioUserAgent,
      ),
    ];
  }

  Future<List<StreamCandidate>> _invidiousCandidates(String videoId) async {
    final urls = await _invidious.audioUrls(videoId);
    return [
      for (final url in urls)
        StreamCandidate(url: url, userAgent: AppConfig.genericAudioUserAgent),
    ];
  }

  /// Идентификатор видео для трека. Spotify-треки (`sp:`) сопоставляются
  /// с YouTube по «исполнитель + название»; соответствие запоминается надолго.
  Future<String?> _videoIdFor(Track track) async {
    final isSpotify = track.source == TrackSource.spotify || track.id.startsWith('sp:');
    if (!isSpotify) return track.id;

    final cached = _matched[track.id] ?? _settings.matchedVideo(track.id);
    if (cached != null && cached.isNotEmpty) {
      _matched[track.id] = cached;
      return cached;
    }

    final artist = track.artist.split(',').first.trim();
    final queries = <String>[
      '$artist ${track.title}'.trim(),
      '${track.title} $artist'.trim(),
      '${track.title} audio'.trim(),
    ];
    for (final query in queries) {
      final candidates = await _safeSearch(query);
      if (candidates.isEmpty) continue;
      final best = pickBestMatch(track, candidates) ?? candidates.first;
      _matched[track.id] = best.id;
      _settings.rememberMatch(track.id, best.id);
      return best.id;
    }
    return null;
  }

  // ------------------------------------------------- совместимость (скачивание)

  Future<List<String>> resolveAudioUrls(Track track) async {
    final candidates = await resolveCandidates(track);
    return [for (final c in candidates) c.url];
  }

  Future<String?> streamUrl(String videoId) async {
    final candidates = await resolveCandidates(Track(id: videoId, title: '', artist: ''));
    return candidates.isEmpty ? null : candidates.first.url;
  }

  Future<String?> streamUrlForTrack(Track track) async {
    final candidates = await resolveCandidates(track);
    return candidates.isEmpty ? null : candidates.first.url;
  }

  Future<Track> resolveTrack(Track track) async {
    final urls = await resolveAudioUrls(track);
    return urls.isEmpty ? track : track.copyWith(streamUrl: urls.first);
  }

  /// Заголовки по умолчанию для аудиопотоков (если неизвестен конкретный клиент).
  Map<String, String> get streamHeaders => {
        'User-Agent': AppConfig.genericAudioUserAgent,
        'Accept': '*/*',
        ..._settings.requestHeaders,
      };
}
