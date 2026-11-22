import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

class SoundCloudService {
  SoundCloudService({
    required Settings settings,
    required Box<dynamic> cache,
  })  : _cache = cache,
        _dio = createDio(
          settings: settings,
          receiveTimeout: const Duration(seconds: 15),
        );

  static const cacheBoxName = 'soundcloud_cache';
  static const _clientIdKey = 'clientIdAt';
  static const _api = 'https://api-v2.soundcloud.com';

  final Box<dynamic> _cache;
  final Dio _dio;

  String? _clientId;
  Future<String?>? _inflight;

  final Map<String, _CachedStream> _streamCache = {};

  Future<String?> clientId({bool force = false}) {
    if (!force && _clientId != null) {
      return Future.value(_clientId);
    }

    if (_inflight != null) {
      return _inflight!;
    }

    final future = _loadClientId(force: force);

    _inflight = future;

    return future.whenComplete(() {
      _inflight = null;
    });
  }

  Future<String?> _loadClientId({
    required bool force,
  }) async {
    if (!force && _freshFromCache()) {
      final cached = _cache.get('clientId') as String?;

      if (cached != null && cached.isNotEmpty) {
        _clientId = cached;
        return cached;
      }
    }

    try {
      final id = await _scrapeClientId();

      if (id != null && id.isNotEmpty) {
        _clientId = id;

        await _cache.put('clientId', id);

        await _cache.put(
          _clientIdKey,
          DateTime.now().millisecondsSinceEpoch,
        );

        return id;
      }
    } catch (_) {
      // Используем сохранённый client_id.
    }

    final stale = _cache.get('clientId') as String?;

    if (stale != null && stale.isNotEmpty) {
      _clientId = stale;
      return stale;
    }

    return null;
  }

  bool _freshFromCache() {
    final at = (_cache.get(_clientIdKey) as num?)?.toInt();

    if (at == null) return false;

    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );

    return age >= Duration.zero &&
        age < AppConfig.soundcloudClientIdTtl;
  }

  Future<String?> _scrapeClientId() async {
    final response = await _dio.getUri<String>(
      Uri.parse('https://soundcloud.com/'),
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'accept': 'text/html',
        },
      ),
    );

    if ((response.statusCode ?? 0) >= 400) {
      return null;
    }

    final html = response.data ?? '';

    final scripts = RegExp(
      r'<script[^>]+src=["'']([^"'']*a-v2\.sndcdn\.com/assets/[^"'']+\.js)[\"'']',
    )
        .allMatches(html)
        .map((m) {
          final raw = m.group(1)!;

          return raw.startsWith('http')
              ? raw
              : 'https://soundcloud.com$raw';
        })
        .toList();

    if (scripts.isEmpty) {
      scripts.addAll(
        RegExp(
          r'https://a-v2\.sndcdn\.com/assets/[^"''\s]+\.js',
        )
            .allMatches(html)
            .map((m) => m.group(0)!),
      );
    }

    for (final url in scripts.take(12)) {
      try {
        final result = await _dio.getUri<String>(
          Uri.parse(url),
          options: Options(
            responseType: ResponseType.plain,
          ),
        );

        final js = result.data ?? '';

        final match = RegExp(
          r'''client_id\s*[:=]\s*["']([A-Za-z0-9]{32})["']''',
        ).firstMatch(js);

        if (match != null) {
          return match.group(1);
        }
      } catch (_) {
        // Следующий JS-бандл.
      }
    }

    return null;
  }

  Future<List<Track>> search(
    String query, {
    int limit = 30,
  }) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return const [];

    var id = await clientId();

    if (id == null) return const [];

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse('$_api/search/tracks').replace(
          queryParameters: {
            'q': trimmed,
            'client_id': id,
            'limit': '${limit.clamp(1, 50)}',
            'app_locale': 'ru',
          },
        );

        final response = await _dio.getUri<String>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
          ),
        );

        final status = response.statusCode ?? 0;

        if (status == 401 || status == 403) {
          _clientId = null;
          id = await clientId(force: true);

          if (id == null) return const [];

          continue;
        }

        if (status < 200 || status >= 300) {
          return const [];
        }

        final body = response.data ?? '{}';

        return await parseJson(
          body,
          (raw) => parseSearchBody(
            raw,
            limit: limit,
          ),
        );
      } catch (_) {
        return const [];
      }
    }

    return const [];
  }

  Future<List<String>> audioUrls(String trackId) async {
    final normalizedId = trackId.startsWith('sc:')
        ? trackId.substring(3)
        : trackId;

    if (normalizedId.isEmpty) return const [];

    final cached = _streamCache[normalizedId];

    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return [cached.url];
    }

    var id = await clientId();

    if (id == null) return const [];

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse('$_api/tracks/$normalizedId').replace(
          queryParameters: {
            'client_id': id,
            'app_locale': 'ru',
          },
        );

        final response = await _dio.getUri<String>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
          ),
        );

        final status = response.statusCode ?? 0;

        if (status == 401 || status == 403) {
          _clientId = null;
          id = await clientId(force: true);

          if (id == null) return const [];

          continue;
        }

        if (status < 200 || status >= 300) {
          return const [];
        }

        final body = response.data;

        if (body == null || body.isEmpty) {
          return const [];
        }

        final parsed = await parseJson(
          body,
          parseTranscodings,
        );

        final result = <String>[];

        for (final transcoding in parsed.urls.take(5)) {
          final url = await _signedUrl(
            transcoding,
            id,
            parsed.authorization,
          );

          if (url != null && !result.contains(url)) {
            result.add(url);
          }
        }

        if (result.isNotEmpty) {
          _streamCache[normalizedId] = _CachedStream(
            result.first,
            DateTime.now().add(
              AppConfig.soundcloudStreamCacheTtl,
            ),
          );
        }

        return result;
      } catch (_) {
        return const [];
      }
    }

    return const [];
  }

  Future<String?> _signedUrl(
    String transcoding,
    String id,
    String? authorization,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final original = Uri.parse(transcoding);

        final query = <String, String>{
          ...original.queryParameters,
          'client_id': id,
          if (authorization != null &&
              authorization.isNotEmpty)
            'track_authorization': authorization,
        };

        final uri = original.replace(
          queryParameters: query,
        );

        final response = await _dio.getUri<dynamic>(
          uri,
          options: Options(
            responseType: ResponseType.json,
          ),
        );

        final status = response.statusCode ?? 0;

        if (status == 401 || status == 403) {
          _clientId = null;

          final fresh = await clientId(force: true);

          if (fresh == null) return null;

          id = fresh;
          continue;
        }

        if (status < 200 || status >= 300) {
          return null;
        }

        final data = response.data;

        dynamic decoded = data;

        if (data is String) {
          decoded = jsonDecode(data);
        }

        final url = decoded is Map
            ? decoded['url']
            : null;

        if (url is String && url.isNotEmpty) {
          return url;
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  Future<String?> streamFor(Track track) async {
    final cached = _streamCache[track.id];

    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now())) {
      return cached.url;
    }

    List<String> urls = const [];

    if (track.id.startsWith('sc:')) {
      urls = await audioUrls(track.id);
    }

    if (urls.isEmpty) {
      final found = pickBest(
        track,
        await search(
          _queryFor(track),
          limit: 10,
        ),
      );

      if (found == null) return null;

      urls = await audioUrls(found.id);
    }

    if (urls.isEmpty) return null;

    return urls.first;
  }

  static String _queryFor(Track track) {
    final artist = track.artist.split(',').first.trim();

    return '$artist ${track.title}'.trim();
  }

  void clearStreamCache() {
    _streamCache.clear();
  }
}

class _CachedStream {
  const _CachedStream(
    this.url,
    this.expiresAt,
  );

  final String url;
  final DateTime expiresAt;
}

String? _asString(dynamic value) {
  return value is String ? value : null;
}

int _asInt(dynamic value) {
  return value is num ? value.toInt() : 0;
}

/// Разбор SoundCloud Search API.
List<Track> parseSearchBody(
  String body, {
  int limit = 30,
}) {
  final json = jsonDecode(body);

  final collection = json is Map
      ? json['collection']
      : null;

  if (collection is! List) return const [];

  final out = <Track>[];

  final seen = <String>{};

  for (final item in collection.whereType<Map>()) {
    if (out.length >= limit) break;

    if (_asString(item['kind']) != 'track') continue;

    if (item['streamable'] == false) continue;

    final id = item['id'];

    if (id is! num) continue;

    final trackId = id.toInt().toString();

    if (!seen.add(trackId)) continue;

    final user = item['user'];

    final artist = user is Map
        ? _asString(user['username'])
        : null;

    final artwork = _asString(item['artwork_url']) ??
        (user is Map
            ? _asString(user['avatar_url'])
            : null);

    out.add(
      Track(
        id: 'sc:$trackId',
        title: _asString(item['title']) ?? 'Без названия',
        artist: (artist ?? 'SoundCloud').trim(),
        duration: Duration(
          milliseconds: _asInt(item['duration']),
        ),
        thumbnailUrl: artwork,
        source: TrackSource.soundcloud,
      ),
    );
  }

  return out;
}

/// Получение доступных аудиотранскодингов.
({
  String? authorization,
  List<String> urls,
}) parseTranscodings(String body) {
  final json = jsonDecode(body);

  if (json is! Map) {
    return (
      authorization: null,
      urls: <String>[],
    );
  }

  final authorization = _asString(
    json['track_authorization'],
  );

  final policy = _asString(json['policy']);

  if (policy == 'BLOCK' || policy == 'SNIP') {
    return (
      authorization: authorization,
      urls: <String>[],
    );
  }

  final media = json['media'];

  final transcodings = media is Map
      ? media['transcodings']
      : null;

  if (transcodings is! List) {
    return (
      authorization: authorization,
      urls: <String>[],
    );
  }

  final progressive = <String>[];
  final hls = <String>[];

  for (final transcoding in transcodings.whereType<Map>()) {
    final format = transcoding['format'];

    if (format is! Map) continue;

    final protocol = _asString(format['protocol']);
    final mime = (_asString(format['mime_type']) ?? '')
        .toLowerCase();

    if (!mime.startsWith('audio/')) continue;

    final url = _asString(transcoding['url']);

    if (url == null || url.isEmpty) continue;

    if (protocol == 'progressive') {
      progressive.add(url);
    } else if (protocol == 'hls' ||
        protocol == 'hls_aac') {
      hls.add(url);
    }
  }

  final urls = <String>[
    ...progressive,
    ...hls,
  ];

  return (
    authorization: authorization,
    urls: urls.toSet().toList(),
  );
}

/// Поиск наиболее подходящего трека.
Track? pickBest(
  Track target,
  List<Track> candidates,
) {
  if (candidates.isEmpty) return null;

  final title = _norm(target.title);

  final artist = _norm(
    target.artist.split(',').first,
  );

  final wantedDuration = target.duration.inSeconds;

  Track? best;

  var bestScore = 0.0;

  for (final candidate in candidates) {
    var score = 0.0;

    final candidateTitle = _norm(candidate.title);
    final candidateArtist = _norm(candidate.artist);

    if (title.isNotEmpty &&
        (candidateTitle == title ||
            candidateTitle.contains(title) ||
            title.contains(candidateTitle))) {
      score += 20;
    }

    if (artist.isNotEmpty &&
        (candidateArtist.contains(artist) ||
            candidateTitle.contains(artist))) {
      score += 10;
    }

    final candidateDuration =
        candidate.duration.inSeconds;

    if (wantedDuration > 0 &&
        candidateDuration > 0) {
      final difference =
          (candidateDuration - wantedDuration).abs();

      if (difference <= 5) {
        score += 10;
      } else if (difference <= 10) {
        score += 5;
      } else if (difference > 30) {
        score -= 10;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return bestScore >= 20 ? best : null;
}

String _norm(String value) {
  return value
      .toLowerCase()
      .replaceAll(
        RegExp(r'[^\p{L}\p{N}]+', unicode: true),
        ' ',
      )
      .trim();
}