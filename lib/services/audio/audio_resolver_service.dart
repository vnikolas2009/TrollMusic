
import '../../core/network/soundcloud/soundcloud_service.dart';
import '../../core/network/youtube/innertube_service.dart';
import '../../core/utils/track_match.dart';
import '../../data/models/track.dart';

/// Единая точка получения аудиопотока.
///
/// Приоритет зависит от источника трека:
/// YouTube: YouTube → SoundCloud.
/// SoundCloud: SoundCloud → YouTube.
/// Spotify: SoundCloud → YouTube.
/// Локальные файлы обрабатываются AudioHandler.
class AudioResolverService {
  AudioResolverService({
    required SoundCloudService soundcloud,
    required InnerTubeService innerTube,
  })  : _soundcloud = soundcloud,
        _innerTube = innerTube;

  final SoundCloudService _soundcloud;
  final InnerTubeService _innerTube;

  final Map<String, List<String>> _cache = {};
  final Map<String, Future<List<String>>> _inflight = {};

  static final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Возвращает список аудиоссылок для трека.
  Future<List<String>> resolve(Track track) {
    if (track.localPath?.isNotEmpty == true) {
      return Future.value(const []);
    }

    final cached = _cache[track.id];
    if (cached != null && cached.isNotEmpty) {
      return Future.value(cached);
    }

    final existing = _inflight[track.id];
    if (existing != null) return existing;

    final future = _resolve(track);
    _inflight[track.id] = future;

    return future.then((urls) {
      if (urls.isNotEmpty) {
        _cache[track.id] = urls;
      }
      return urls;
    }).whenComplete(() {
      _inflight.remove(track.id);
    });
  }

  Future<String?> resolveTrackUrl(Track track) async {
    final urls = await resolve(track);
    return urls.isEmpty ? null : urls.first;
  }

  /// Заголовки для потоков YouTube.
  Map<String, String> streamHeaders(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';

    final isGoogleVideo = host == 'googlevideo.com' ||
        host.endsWith('.googlevideo.com');

    final isYouTube = host == 'youtube.com' ||
        host.endsWith('.youtube.com');

    if (isGoogleVideo || isYouTube) {
      return InnerTubeService.androidVrStreamHeaders;
    }

    return const {};
  }

  Future<List<Track>> searchSoundCloud(
    String query, {
    int limit = 30,
  }) {
    return _soundcloud
        .search(query, limit: limit)
        .catchError((_) => const <Track>[]);
  }

  Future<List<Track>> searchYouTube(
    String query, {
    int limit = 30,
  }) {
    return _innerTube
        .search(query, limit: limit)
        .catchError((_) => const <Track>[]);
  }

  /// Рекомендации для пустой медиатеки.
  Future<List<Track>> trending() async {
    final youtube = await searchYouTube('популярная музыка 2026');

    if (youtube.isNotEmpty) {
      return youtube;
    }

    return searchSoundCloud('популярная музыка');
  }

  /// Удаляет сохранённые ссылки трека.
  void forget(String trackId) {
    _cache.remove(trackId);
  }

  /// Очищает весь кэш ссылок.
  void clearCache() {
    _cache.clear();
  }

  Future<List<String>> _resolve(Track track) async {
    final known = (track.streamUrl ?? '').trim();

    if (known.isNotEmpty) {
      return [known];
    }

    final urls = <String>[];

    switch (track.source) {
      case TrackSource.youtube:
        await _resolveYouTubeFirst(track, urls);
        if (urls.isEmpty) {
          await _resolveSoundCloud(track, urls);
        }

      case TrackSource.soundcloud:
        await _resolveSoundCloud(track, urls);
        if (urls.isEmpty) {
          await _resolveYouTube(track, urls);
        }

      case TrackSource.spotify:
        await _resolveSoundCloud(track, urls);
        if (urls.isEmpty) {
          await _resolveYouTube(track, urls);
        }

      case TrackSource.local:
      case TrackSource.downloaded:
        break;
    }

    return _dedupe(urls);
  }

  Future<void> _resolveYouTubeFirst(
    Track track,
    List<String> result,
  ) async {
    final id = track.id;

    if (_videoId.hasMatch(id)) {
      result.addAll(
        await _innerTube.audioUrls(id).catchError(
          (_) => const <String>[],
        ),
      );
      return;
    }

    await _resolveYouTube(track, result);
  }

  Future<void> _resolveYouTube(
    Track track,
    List<String> result,
  ) async {
    final videoId = await _findVideoId(track);

    if (videoId == null) return;

    final urls = await _innerTube.audioUrls(videoId).catchError(
      (_) => const <String>[],
    );

    result.addAll(urls);
  }

  Future<void> _resolveSoundCloud(
    Track track,
    List<String> result,
  ) async {
    final url = await _soundcloud.streamFor(track);

    if (url != null && url.trim().isNotEmpty) {
      result.add(url);
    }
  }

  Future<String?> _findVideoId(Track track) async {
    final artist = track.artist.split(',').first.trim();

    final queries = <String>[
      '$artist ${track.title}'.trim(),
      '${track.title} $artist'.trim(),
      '${track.title} official audio'.trim(),
    ];

    for (final query in queries) {
      if (query.isEmpty) continue;

      final candidates = await searchYouTube(query);

      if (candidates.isEmpty) continue;

      final best = pickBestMatch(track, candidates);

      if (best != null && _videoId.hasMatch(best.id)) {
        return best.id;
      }
    }

    return null;
  }

  List<String> _dedupe(Iterable<String> input) {
    final seen = <String>{};

    return [
      for (final url in input)
        if (url.trim().isNotEmpty && seen.add(url.trim()))
          url.trim(),
    ];
  }
}
