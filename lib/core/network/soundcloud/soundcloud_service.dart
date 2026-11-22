import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

/// SoundCloud без OAuth: публичный `client_id` со страницы приложения
/// (кэш в Hive на 24 часа) + api-v2. Аудио отдаётся напрямую (MP3/HLS),
/// без посредников.
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

  final Map<String, String> _streamCache = {};

  Future<String?> clientId({bool force = false}) {
    if (!force && _clientId != null) return Future.value(_clientId);
    return _inflight ??= _loadClientId(force: force).whenComplete(() {
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
      if (id != null) {
        _clientId = id;
        await _cache.put('clientId', id);
        await _cache.put(_clientIdKey, DateTime.now().millisecondsSinceEpoch);
        return id;
      }
    } catch (_) {
      // Ниже — старый id из кэша, даже просроченный: лучше, чем ничего.
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
    return age < AppConfig.soundcloudClientIdTtl;
  }

  /// Ищет `client_id` в JS-бандлах страницы soundcloud.com.
  Future<String?> _scrapeClientId() async {
    final home = await _dio.getUri<String>(
      Uri.parse('https://soundcloud.com/'),
      options: Options(
        responseType: ResponseType.plain,
        headers: {'accept': 'text/html'},
      ),
    );
    final html = home.data ?? '';
    final scripts = RegExp(
      r'<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
    ).allMatches(html).map((m) => m.group(1)!).toList();

    final assets = scripts.isNotEmpty
        ? scripts
        : RegExp(r'https://a-v2\.sndcdn\.com/assets/[^"\\\s]+\.js')
            .allMatches(html)
            .map((m) => m.group(0)!)
            .toSet()
            .toList();

    for (final url in assets.take(8)) {
      try {
        final res = await _dio.getUri<String>(
          Uri.parse(url),
          options: Options(responseType: ResponseType.plain),
        );
        final match = RegExp(
          r'client_id:"([A-Za-z0-9]{32})"',
        ).firstMatch(res.data ?? '') ??
            RegExp(r'client_id=([A-Za-z0-9]{32})').firstMatch(res.data ?? '');
        if (match != null) return match.group(1);
      } catch (_) {
        // Следующий бандл.
      }
    }
    return null;
  }

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final id = await clientId();
    if (id == null) return const [];
    try {
      final res = await _dio.getUri<String>(
        Uri.parse('$_api/search/tracks').replace(queryParameters: {
          'q': query,
          'client_id': id,
          'limit': '$limit',
          'app_locale': 'ru',
        }),
        options: Options(responseType: ResponseType.plain),
      );
      final body = res.data ?? '{}';
      return await parseJson(body, (raw) => parseSearchBody(raw, limit: limit));
    } catch (_) {
      return const [];
    }
  }

  /// Прямые ссылки на аудио для трека SoundCloud (по его числовому id).
  Future<List<String>> audioUrls(String trackId) async {
    final id = await clientId();
    if (id == null) return const [];

    final tracksId = trackId.startsWith('sc:') ? trackId.substring(3) : trackId;
    try {
      final res = await _dio.getUri<String>(
        Uri.parse('$_api/tracks/$tracksId').replace(queryParameters: {
          'client_id': id,
          'app_locale': 'ru',
        }),
        options: Options(responseType: ResponseType.plain),
      );
      final body = res.data;
      if (body == null || body.isEmpty) return const [];
      final parsed = await parseJson(body, parseTranscodings);
      final out = <String>[];
      for (final transcoding in parsed.urls.take(3)) {
        final direct = await _signedUrl(transcoding, id, parsed.authorization);
        if (direct != null && !out.contains(direct)) out.add(direct);
        if (out.isNotEmpty) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Транскодинг → реальная ссылка на файл/плейлист (`{"url": ...}`).
  Future<String?> _signedUrl(String transcoding, String id, String? auth) async {
    try {
      final res = await _dio.getUri<dynamic>(
        Uri.parse(transcoding).replace(queryParameters: {
          'client_id': id,
          if (auth != null) 'track_authorization': auth,
        }),
        options: Options(responseType: ResponseType.json),
      );
      final data = res.data;
      final url = data is Map ? data['url'] : null;
      return url is String && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// Поток для произвольного трека: `sc:` — по id, иначе поиск по метаданным.
  Future<String?> streamFor(Track track) async {
    final cached = _streamCache[track.id];
    if (cached != null) return cached;

    var urls = const <String>[];
    if (track.id.startsWith('sc:')) {
      urls = await audioUrls(track.id);
    }
    if (urls.isEmpty) {
      final found = pickBest(track, await search(_queryFor(track), limit: 10));
      if (found == null) return null;
      urls = await audioUrls(found.id);
    }
    if (urls.isEmpty) return null;
    _streamCache[track.id] = urls.first;
    return urls.first;
  }

  static String _queryFor(Track track) {
    final artist = track.artist.split(',').first.trim();
    return '$artist ${track.title}'.trim();
  }
}

String? _asString(dynamic value) => value is String ? value : null;

int _asInt(dynamic value) => value is num ? value.toInt() : 0;

/// Разбор `/search/tracks`. Top-level: выполняется в изоляте.
List<Track> parseSearchBody(String body, {int limit = 30}) {
  final json = jsonDecode(body);
  final collection = json is Map ? json['collection'] : null;
  if (collection is! List) return const [];

  final out = <Track>[];
  for (final item in collection.whereType<Map>()) {
    if (out.length >= limit) break;
    if (_asString(item['kind']) != 'track') continue;
    if (item['streamable'] == false) continue;
    final id = item['id'];
    if (id is! num) continue;

    final user = item['user'];
    final artist = user is Map ? _asString(user['username']) : null;
    final artwork = _asString(item['artwork_url']) ??
        (user is Map ? _asString(user['avatar_url']) : null);

    out.add(Track(
      id: 'sc:${id.toInt()}',
      title: _asString(item['title']) ?? 'Без названия',
      artist: (artist ?? 'SoundCloud').trim(),
      duration: Duration(milliseconds: _asInt(item['duration'])),
      thumbnailUrl: artwork,
      source: TrackSource.soundcloud,
    ));
  }
  return out;
}

/// Достаёт ссылки транскодингов из `media.transcodings`.
/// Top-level: выполняется в изоляте.
({String? authorization, List<String> urls}) parseTranscodings(String body) {
  final json = jsonDecode(body);
  if (json is! Map) return (authorization: null, urls: const <String>[]);
  final auth = _asString(json['track_authorization']);
  final policy = _asString(json['policy']);
  if (policy == 'BLOCK' || policy == 'SNIP') {
    return (authorization: auth, urls: const <String>[]);
  }

  final out = <String>[];
  final media = json['media'];
  final transcodings = media is Map ? media['transcodings'] : null;
  if (transcodings is List) {
    // Два прохода: сначала прогрессивный MP3, затем HLS.
    for (final wantProgressive in [true, false]) {
      for (final t in transcodings.whereType<Map>()) {
        final format = t['format'];
        if (format is! Map) continue;
        final protocol = _asString(format['protocol']);
        final mime = _asString(format['mime_type']) ?? '';
        if (!mime.contains('mpeg') && !mime.contains('mp4')) continue;
        final progressive = protocol == 'progressive';
        if (progressive != wantProgressive) continue;
        final url = _asString(t['url']);
        if (url == null || url.isEmpty) continue;
        if (out.contains(url)) continue;
        out.add(url);
      }
    }
  }

  return (authorization: auth, urls: out);
}

/// Совпадение по нормализованному «исполнитель + название».
Track? pickBest(Track target, List<Track> candidates) {
  if (candidates.isEmpty) return null;
  final title = _norm(target.title);
  final artist = _norm(target.artist.split(',').first);
  final want = target.duration.inSeconds;

  Track? best;
  var bestScore = 0.0;
  for (final c in candidates) {
    var score = 0.0;
    final cTitle = _norm(c.title);
    final cArtist = _norm(c.artist);
    if (title.isNotEmpty && cTitle.contains(title)) score += 20;
    if (artist.isNotEmpty && (cArtist.contains(artist) || cTitle.contains(artist))) {
      score += 10;
    }
    final have = c.duration.inSeconds;
    if (want > 0 && have > 0 && (have - want).abs() <= 8) score += 8;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }
  // Слабое совпадение (например, только по названию) не считаем попаданием.
  return bestScore >= 20 ? best : null;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
