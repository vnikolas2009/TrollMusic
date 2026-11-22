import '../../core/config/app_config.dart';
import '../../core/network/soundcloud/soundcloud_service.dart';
import '../../core/network/youtube/innertube_service.dart';
import '../../core/utils/track_match.dart';
import '../../data/models/track.dart';

class AudioResolverService {
  AudioResolverService({
    required SoundCloudService soundcloud,
    required InnerTubeService innerTube,
  })  : _soundcloud = soundcloud,
        _innerTube = innerTube;

  final SoundCloudService _soundcloud;
  final InnerTubeService _innerTube;

  static final _videoId = RegExp(
    r'^[A-Za-z0-9_-]{11}$',
  );

  static const _cacheTtl = Duration(minutes: 10);

  final Map<String, _ResolvedCache> _cache = {};

  final Map<String, Future<List<String>>> _inflight = {};

  /// Получение всех доступных кандидатов.
  Future<List<String>> resolve(Track track) {
    final local = track.localPath;

    if (local != null && local.isNotEmpty) {
      return Future.value(const []);
    }

    final cached = _cache[track.id];

    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return Future.value(cached.urls);
    }

    if (cached != null) {
      _cache.remove(track.id);
    }

    final existing = _inflight[track.id];

    if (existing != null) return existing;

    final future = _resolve(track);

    _inflight[track.id] = future;

    return future.then((urls) {
      if (urls.isNotEmpty) {
        _cache[track.id] = _ResolvedCache(
          urls,
          DateTime.now().add(_cacheTtl),
        );
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

  /// Заголовки для прямых YouTube-потоков.
  Map<String, String> streamHeaders(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';

    if (host.endsWith('googlevideo.com') ||
        host.contains('youtube.com')) {
      return InnerTubeService.androidVrStreamHeaders;
    }

    return const {};
  }

  Future<List<Track>> searchSoundCloud(
    String query, {
    int limit = 30,
  }) {
    return _soundcloud.search(
      query,
      limit: limit,
    ).catchError(
      (_) => const <Track>[],
    );
  }

  Future<List<Track>> searchYouTube(
    String query, {
    int limit = 30,
  }) {
    return _innerTube.search(
      query,
      limit: limit,
    ).catchError(
      (_) => const <Track>[],
    );
  }

  Future<List<Track>> trending() async {
    final youtube = await searchYouTube(
      'популярная музыка 2026',
    );

    if (youtube.isNotEmpty) return youtube;

    return searchSoundCloud(
      'популярная музыка',
    );
  }

  /// Сбрасывает кэш после ошибки воспроизведения.
  void forget(String trackId) {
    _cache.remove(trackId);

    _soundcloud.forget(trackId);
    _innerTube.forget(trackId);
  }

  Future<List<String>> _resolve(Track track) async {
    final known = (track.streamUrl ?? '').trim();

    if (known.isNotEmpty) {
      return [known];
    }

    final soundCloudFirst =
        track.source != TrackSource.youtube;

    final urls = <String>[];

    if (soundCloudFirst) {
      urls.addAll(
        await _resolveSoundCloud(track),
      );

      urls.addAll(
        await _resolveYouTube(track),
      );
    } else {
      urls.addAll(
        await _resolveYouTube(track),
      );

      urls.addAll(
        await _resolveSoundCloud(track),
      );
    }

    return _dedupe(urls);
  }

  /// Получение нескольких SoundCloud-потоков.
  Future<List<String>> _resolveSoundCloud(
    Track track,
  ) async {
    try {
      if (track.id.startsWith('sc:')) {
        return await _soundcloud.audioUrls(track.id);
      }

      final query = _queryFor(track);

      final candidates = await _soundcloud.search(
        query,
        limit: 10,
      );

      final best = pickBestMatch(
        track,
        candidates,
      );

      if (best == null) return const [];

      return await _soundcloud.audioUrls(best.id);
    } catch (_) {
      return const [];
    }
  }

  /// Получение нескольких YouTube-потоков.
  Future<List<String>> _resolveYouTube(
    Track track,
  ) async {
    try {
      final id = _videoId.hasMatch(track.id)
          ? track.id
          : await _findVideoId(track);

      if (id == null) return const [];

      return await _innerTube.audioUrls(id);
    } catch (_) {
      return const [];
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

      final candidates = await searchYouTube(
        query,
        limit: 15,
      );

      if (candidates.isEmpty) continue;

      final best = pickBestMatch(
        track,
        candidates,
      );

      if (best != null) return best.id;
    }

    return null;
  }

  static String _queryFor(Track track) {
    final artist = track.artist.split(',').first.trim();

    return '$artist ${track.title}'.trim();
  }

  List<String> _dedupe(Iterable<String> input) {
    final seen = <String>{};

    return [
      for (final url in input)
        if (url.isNotEmpty && seen.add(url))
          url,
    ];
  }

  void clearCache() {
    _cache.clear();

    _soundcloud.clearStreamCache();
    _innerTube.clearCache();
  }
}

class _ResolvedCache {
  const _ResolvedCache(
    this.urls,
    this.expiresAt,
  );

  final List<String> urls;
  final DateTime expiresAt;
}