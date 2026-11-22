import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

class SoundCloudService {
  SoundCloudService({required Settings settings, required Box<dynamic> cache})
    : _cache = cache,
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

  Future<String?> _loadClientId({required bool force}) async {
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
        await _cache.put(_clientIdKey, DateTime.now().millisecondsSinceEpoch);

        return id;
      }
    } catch (_) {
      // При ошибке используем сохранённый client_id.
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

    return age >= Duration.zero && age < AppConfig.soundcloudClientIdTtl;
  }

  Future<String?> _scrapeClientId() async {
    final response = await _dio.getUri<String>(
      Uri.parse('https://soundcloud.com/'),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'accept': 'text/html'},
      ),
    );

    if ((response.statusCode ?? 0) >= 400) {
      return null;
    }

    final html = response.data ?? '';

    final scriptPattern = RegExp(
      r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    );

    final scripts = <String>[];

    for (final match in scriptPattern.allMatches(html)) {
      final raw = match.group(1);

      if (raw == null || raw.isEmpty) continue;

      final uri = Uri.tryParse(raw);

      if (uri == null) continue;

      final resolved = Uri.parse('https://soundcloud.com/').resolveUri(uri);

      if (resolved.host != 'a-v2.sndcdn.com' &&
          resolved.host != 'soundcloud.com') {
        continue;
      }

      if (!resolved.path.contains('/assets/') ||
          !resolved.path.endsWith('.js')) {
        continue;
      }

      final url = resolved.toString();

      if (!scripts.contains(url)) {
        scripts.add(url);
      }
    }

    for (final url in scripts.take(12)) {
      try {
        final result = await _dio.getUri<String>(
          Uri.parse(url),
          options: Options(
            responseType: ResponseType.plain,
            headers: const {'accept': '*/*'},
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
        // Проверяем следующий JS-бандл.
      }
    }

    return null;
  }

  Future<List<Track>> search(String query, {int limit = 30}) async {
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
          options: Options(responseType: ResponseType.plain),
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
          (raw) => parseSearchBody(raw, limit: limit),
        );
      } catch (_) {
        return const [];
      }
    }

    return const [];
  }

  /// Возвращает все доступные аудиоссылки трека.
  ///
  /// Progressive-ссылки идут раньше HLS.
  /// Ссылки кэшируются вместе, а не только первая из них.
  Future<List<String>> audioUrls(String trackId) async {
    final normalizedId = _normalizeTrackId(trackId);

    if (normalizedId.isEmpty) return const [];

    final cached = _streamCache[normalizedId];

    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return List<String>.unmodifiable(cached.urls);
    }

    _streamCache.remove(normalizedId);

    var id = await clientId();

    if (id == null) return const [];

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse('$_api/tracks/$normalizedId')
            .replace(queryParameters: {'client_id': id, 'app_locale': 'ru'});

        final response = await _dio.getUri<String>(
          uri,
          options: Options(responseType: ResponseType.plain),
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

        final parsed = await parseJson(body, parseTranscodings);

        final result = <String>[];

        for (final transcoding in parsed.urls.take(8)) {
          final url = await _signedUrl(transcoding, id, parsed.authorization);

          if (url != null && !result.contains(url)) {
            result.add(url);
          }
        }

        if (result.isNotEmpty) {
          _streamCache[normalizedId] = _CachedStream(
            List<String>.unmodifiable(result),
            DateTime.now().add(AppConfig.soundcloudStreamCacheTtl),
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

        if (original.scheme != 'https' ||
            (original.host != 'api-v2.soundcloud.com' &&
                original.host != 'api.soundcloud.com')) {
          return null;
        }

        final query = <String, String>{
          ...original.queryParameters,
          'client_id': id,
          if (authorization != null && authorization.isNotEmpty)
            'track_authorization': authorization,
        };

        final uri = original.replace(queryParameters: query);

        final response = await _dio.getUri<dynamic>(
          uri,
          options: Options(responseType: ResponseType.json),
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

        final url = decoded is Map ? decoded['url'] : null;

        if (url is String && url.isNotEmpty) {
          final streamUri = Uri.tryParse(url);

          if (streamUri == null || streamUri.scheme != 'https') {
            return null;
          }

          return url;
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Получает первую доступную ссылку для совместимости
  /// с кодом, который ожидает один URL.
  Future<String?> streamFor(Track track) async {
    final urls = await streamUrlsFor(track);

    return urls.isEmpty ? null : urls.first;
  }

  /// Получает несколько ссылок, включая поиск замены,
  /// если исходный трек недоступен.
  Future<List<String>> streamUrlsFor(Track track) async {
    final normalizedId = _normalizeTrackId(track.id);

    if (normalizedId.isNotEmpty) {
      final direct = await audioUrls(normalizedId);

      if (direct.isNotEmpty) {
        return direct;
      }
    }

    final found = pickBest(track, await search(_queryFor(track), limit: 10));

    if (found == null) return const [];

    return audioUrls(found.id);
  }

  static String _normalizeTrackId(String id) {
    final normalized = id.startsWith('sc:') ? id.substring(3) : id;

    if (normalized.isEmpty || !RegExp(r'^\d+$').hasMatch(normalized)) {
      return '';
    }

    return normalized;
  }

  static String _queryFor(Track track) {
    final artist = track.artist.split(',').first.trim();

    return '$artist ${track.title}'.trim();
  }

  /// Удаляет кэш конкретного трека.
  void forget(String trackId) {
    final normalizedId = _normalizeTrackId(trackId);

    if (normalizedId.isNotEmpty) {
      _streamCache.remove(normalizedId);
    }
  }

  /// Удаляет весь кэш аудиоссылок.
  void clearStreamCache() {
    _streamCache.clear();
  }

  /// Освобождает HTTP-клиент.
  void dispose() {
    _dio.close();
  }
}

class _CachedStream {
  const _CachedStream(this.urls, this.expiresAt);

  final List<String> urls;
  final DateTime expiresAt;
}

String? _asString(dynamic value) {
  return value is String ? value : null;
}

int _asInt(dynamic value) {
  return value is num ? value.toInt() : 0;
}

/// Разбор SoundCloud Search API.
List<Track> parseSearchBody(String body, {int limit = 30}) {
  final json = jsonDecode(body);

  final collection = json is Map ? json['collection'] : null;

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

    final artist = user is Map ? _asString(user['username']) : null;

    final artwork =
        _asString(item['artwork_url']) ??
        (user is Map ? _asString(user['avatar_url']) : null);

    out.add(
      Track(
        id: 'sc:$trackId',
        title: _asString(item['title']) ?? 'Без названия',
        artist: (artist ?? 'SoundCloud').trim(),
        duration: Duration(milliseconds: _asInt(item['duration'])),
        thumbnailUrl: artwork,
        source: TrackSource.soundcloud,
      ),
    );
  }

  return out;
}

/// Получение доступных аудиотранскодингов.
({String? authorization, List<String> urls}) parseTranscodings(String body) {
  final json = jsonDecode(body);

  if (json is! Map) {
    return (authorization: null, urls: <String>[]);
  }

  final authorization = _asString(json['track_authorization']);
  final policy = _asString(json['policy']);

  if (policy == 'BLOCK' || policy == 'SNIP') {
    return (authorization: authorization, urls: <String>[]);
  }

  final media = json['media'];

  final transcodings = media is Map ? media['transcodings'] : null;

  if (transcodings is! List) {
    return (authorization: authorization, urls: <String>[]);
  }

  final progressive = <String>[];
  final hls = <String>[];

  for (final transcoding in transcodings.whereType<Map>()) {
    final format = transcoding['format'];

    if (format is! Map) continue;

    final protocol = _asString(format['protocol']);
    final mime = (_asString(format['mime_type']) ?? '').toLowerCase();

    if (!mime.startsWith('audio/')) continue;

    final url = _asString(transcoding['url']);

    if (url == null || url.isEmpty) continue;

    if (protocol == 'progressive') {
      progressive.add(url);
    } else if (protocol == 'hls' || protocol == 'hls_aac') {
      hls.add(url);
    }
  }

  return (
    authorization: authorization,
    urls: [...progressive, ...hls].toSet().toList(),
  );
}

/// Поиск наиболее подходящего трека.
///
/// Важно: совпадение только исполнителя и длительности
/// не считается достаточным. Название тоже должно совпасть.
Track? pickBest(Track target, List<Track> candidates) {
  if (candidates.isEmpty) return null;

  final title = _norm(target.title);
  final artist = _norm(target.artist.split(',').first);
  final wantedDuration = target.duration.inSeconds;

  if (title.isEmpty) return null;

  Track? best;
  var bestScore = 0.0;

  for (final candidate in candidates) {
    final candidateTitle = _norm(candidate.title);
    final candidateArtist = _norm(candidate.artist);

    final titleMatches =
        candidateTitle == title ||
        candidateTitle.contains(title) ||
        title.contains(candidateTitle);

    if (!titleMatches) continue;

    var score = 20.0;

    if (artist.isNotEmpty &&
        (candidateArtist.contains(artist) || candidateTitle.contains(artist))) {
      score += 10;
    }

    final candidateDuration = candidate.duration.inSeconds;

    if (wantedDuration > 0 && candidateDuration > 0) {
      final difference = (candidateDuration - wantedDuration).abs();

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

  return best;
}

String _norm(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
