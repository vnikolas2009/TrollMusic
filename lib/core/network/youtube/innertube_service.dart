import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../doh_resolver.dart';
import '../http_client.dart';

class InnerTubeService {
  InnerTubeService({
    required Settings settings,
    DohResolver? resolver,
  })  : _settings = settings,
        _youtube = _createClient(
          settings,
          resolver ?? DohResolver.shared,
        );

  final Settings _settings;
  final YoutubeExplode _youtube;

  final Map<String, _YoutubeCache> _cache = {};

  final Map<String, Future<List<String>>> _inflight = {};

  static const androidVrStreamHeaders = {
    'User-Agent':
        'com.google.android.apps.youtube.vr.oculus/1.60.19 '
        '(Linux; U; Android 12L; eureka-user '
        'Build/SQ3A.220605.009.A1) gzip',
    'Accept': '*/*',
  };

  static YoutubeExplode _createClient(
    Settings settings,
    DohResolver resolver,
  ) {
    final client = HttpClient()
      ..connectionTimeout = AppConfig.connectTimeout
      ..idleTimeout = const Duration(seconds: 20);

    configureProxy(client, settings);

    client.connectionFactory = resolver.connect;

    return YoutubeExplode(
      httpClient: YoutubeHttpClient(
        IOClient(client),
      ),
    );
  }

  /// Поиск музыкальных видео YouTube.
  Future<List<Track>> search(
    String query, {
    int limit = 30,
  }) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return const [];

    try {
      final results = await _youtube.search
          .search(trimmed)
          .timeout(AppConfig.requestTimeout);

      final tracks = <Track>[];

      final seen = <String>{};

      for (final video in results) {
        if (tracks.length >= limit) break;

        if (video.isLive) continue;

        final id = _extractVideoId(video.url);

        if (id == null || !seen.add(id)) continue;

        tracks.add(
          Track(
            id: id,
            title: video.title,
            artist: video.author,
            duration: video.duration ?? Duration.zero,
            thumbnailUrl: video.thumbnails.highResUrl,
            source: TrackSource.youtube,
          ),
        );
      }

      return tracks;
    } catch (_) {
      return const [];
    }
  }

  /// Получение аудиоссылок.
  ///
  /// Используется YoutubeExplode вместо ручного разбора cipher.
  Future<List<String>> audioUrls(String videoId) {
    final id = _extractVideoId(videoId) ?? videoId;

    if (id.isEmpty) {
      return Future.value(const []);
    }

    final cached = _cache[id];

    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return Future.value(cached.urls);
    }

    final existing = _inflight[id];

    if (existing != null) return existing;

    final future = _loadAudioUrls(id);

    _inflight[id] = future;

    return future.whenComplete(() {
      _inflight.remove(id);
    });
  }

  Future<List<String>> _loadAudioUrls(
    String videoId,
  ) async {
    try {
      final manifest = await _youtube.videos.streams
          .getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.safari,
              YoutubeApiClient.androidVr,
            ],
          )
          .timeout(
            AppConfig.playbackTimeout,
          );

      final streams = manifest.audioOnly.toList();

      if (streams.isEmpty) {
        return const [];
      }

      final targetBitrate = _settings.bitrate * 1000;

      streams.sort((a, b) {
        final codecA = _codecRank(a.audioCodec);
        final codecB = _codecRank(b.audioCodec);

        if (codecA != codecB) {
          return codecA.compareTo(codecB);
        }

        final bitrateA =
            (a.bitrate.bitsPerSecond - targetBitrate).abs();

        final bitrateB =
            (b.bitrate.bitsPerSecond - targetBitrate).abs();

        return bitrateA.compareTo(bitrateB);
      });

      final urls = <String>[];

      for (final stream in streams) {
        final url = stream.url.toString();

        if (url.isEmpty || urls.contains(url)) continue;

        urls.add(url);

        if (urls.length >= 3) break;
      }

      if (urls.isNotEmpty) {
        _cache[videoId] = _YoutubeCache(
          urls,
          DateTime.now().add(
            const Duration(minutes: 15),
          ),
        );
      }

      return urls;
    } catch (_) {
      return const [];
    }
  }

  int _codecRank(String codec) {
    final value = codec.toLowerCase();

    final isOpus = value.contains('opus');

    if (_settings.preferOpus) {
      return isOpus ? 0 : 1;
    }

    final isAac = value.contains('mp4a') ||
        value.contains('aac');

    return isAac ? 0 : 1;
  }

  static String? _extractVideoId(String value) {
    final uri = Uri.tryParse(value);

    if (uri == null) {
      return RegExp(r'^[A-Za-z0-9_-]{11}$')
              .hasMatch(value)
          ? value
          : null;
    }

    final queryId = uri.queryParameters['v'];

    if (queryId != null &&
        RegExp(r'^[A-Za-z0-9_-]{11}$')
            .hasMatch(queryId)) {
      return queryId;
    }

    if (uri.host == 'youtu.be' &&
        uri.pathSegments.isNotEmpty) {
      final id = uri.pathSegments.first;

      if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
        return id;
      }
    }

    final segments = uri.pathSegments;

    if (segments.length >= 2 &&
        ['embed', 'shorts', 'live'].contains(segments.first)) {
      final id = segments[1];

      if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
        return id;
      }
    }

    return null;
  }

  void clearCache() {
    _cache.clear();
  }

  void forget(String videoId) {
    final id = _extractVideoId(videoId) ?? videoId;
    _cache.remove(id);
  }

  void close() {
    _cache.clear();
    _youtube.close();
  }
}

class _YoutubeCache {
  const _YoutubeCache(
    this.urls,
    this.expiresAt,
  );

  final List<String> urls;
  final DateTime expiresAt;
}

/// Старый JSON-парсер оставлен для совместимости
/// с существующими тестами.
List<Track> parseSearchBody(
  String body, {
  int limit = 30,
}) {
  final data = jsonDecode(body);

  final tracks = <Track>[];
  final seen = <String>{};

  void walk(dynamic node) {
    if (tracks.length >= limit) return;

    if (node is Map) {
      final renderer = node['videoRenderer'];

      if (renderer is Map) {
        final track = _videoToTrack(renderer);

        if (track != null && seen.add(track.id)) {
          tracks.add(track);
        }
      }

      for (final value in node.values) {
        walk(value);
      }
    } else if (node is List) {
      for (final value in node) {
        walk(value);
      }
    }
  }

  walk(data);

  return tracks;
}

/// Совместимость со старыми тестами.
/// В рабочем получении потоков больше не используется.
List<String> parseAudioBody(
  String body, {
  required int target,
  required bool preferOpus,
}) {
  final data = jsonDecode(body);

  if (data is! Map) return const [];

  final streaming = data['streamingData'];

  if (streaming is! Map) return const [];

  final formats =
      (streaming['adaptiveFormats'] as List?) ?? const [];

  final scored = <({int score, String url})>[];

  for (final raw in formats) {
    if (raw is! Map) continue;

    final mime =
        '${raw['mimeType'] ?? ''}'.toLowerCase();

    if (!mime.startsWith('audio/')) continue;

    final url = raw['url'];

    if (url is! String || url.isEmpty) continue;

    final bitrate =
        (raw['bitrate'] as num?)?.toInt() ?? 128000;

    final kbps = bitrate > 10000
        ? bitrate ~/ 1000
        : bitrate;

    final isOpus =
        mime.contains('opus') || mime.contains('webm');

    var score =
        kbps - (kbps - target).abs() ~/ 2;

    if (isOpus) {
      score += preferOpus ? 60 : -40;
    }

    scored.add((
      score: score,
      url: url,
    ));
  }

  scored.sort(
    (a, b) => b.score.compareTo(a.score),
  );

  final out = <String>[];

  for (final item in scored) {
    if (!out.contains(item.url)) {
      out.add(item.url);
    }

    if (out.length >= 3) break;
  }

  final hls = streaming['hlsManifestUrl'];

  if (hls is String && hls.isNotEmpty) {
    out.add(hls);
  }

  return out;
}

Track? _videoToTrack(Map json) {
  final id = json['videoId'];

  if (id is! String || id.isEmpty) return null;

  final title = _runsText(json['title']) ?? 'Без названия';

  final artist = _runsText(json['ownerText']) ??
      _runsText(json['longBylineText']) ??
      _runsText(json['shortBylineText']) ??
      'YouTube';

  final duration = _parseDuration(
    _runsText(json['lengthText']),
  );

  final thumbs = json['thumbnail'] is Map
      ? json['thumbnail']['thumbnails']
      : null;

  String? thumb;

  if (thumbs is List && thumbs.isNotEmpty) {
    final last = thumbs.last;

    if (last is Map && last['url'] is String) {
      thumb = last['url'] as String;
    }
  }

  return Track(
    id: id,
    title: title,
    artist: artist,
    duration: duration,
    thumbnailUrl: thumb,
    source: TrackSource.youtube,
  );
}

String? _runsText(dynamic node) {
  if (node is Map) {
    final runs = node['runs'];

    if (runs is List && runs.isNotEmpty) {
      return runs
          .whereType<Map>()
          .map((r) => '${r['text'] ?? ''}')
          .join()
          .trim();
    }

    final simple = node['simpleText'];

    if (simple is String) return simple;
  }

  if (node is String) return node;

  return null;
}

Duration _parseDuration(String? raw) {
  if (raw == null || raw.isEmpty) {
    return Duration.zero;
  }

  var seconds = 0;

  for (final part in raw.split(':')) {
    seconds = seconds * 60 +
        (int.tryParse(part.trim()) ?? 0);
  }

  return Duration(seconds: seconds);
}