import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../network/http_client.dart';
import '../../network/proxy.dart';
import '../../storage/settings.dart';

const _browserUa =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0 Mobile Safari/537.36';

class SpotifyClient {
  SpotifyClient({required Settings settings, required ProxyConfig proxy})
      : _settings = settings,
        _proxy = proxy,
        _dio = createDio();

  final Settings _settings;
  final ProxyConfig _proxy;
  final Dio _dio;

  String? _token;
  DateTime? _expiresAt;

  bool get hasCredentials =>
      _settings.spotifyClientId.isNotEmpty && _settings.spotifyClientSecret.isNotEmpty;

  Future<bool> ensureToken() async {
    if (!hasCredentials) return false;
    try {
      return await _fetchToken();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fetchToken() async {
    if (_token != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!.subtract(const Duration(seconds: 30)))) {
      return true;
    }
    final basic = base64Encode(
      utf8.encode('${_settings.spotifyClientId}:${_settings.spotifyClientSecret}'),
    );
    final response = await _dio.postUri<Map<String, dynamic>>(
      _proxy.spotifyAccounts('/api/token'),
      data: 'grant_type=client_credentials',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {'authorization': 'Basic $basic'},
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    final token = data?['access_token'] as String?;
    if (token == null) return false;
    _token = token;
    _expiresAt = DateTime.now().add(
      Duration(seconds: (data?['expires_in'] as num?)?.toInt() ?? 3600),
    );
    return true;
  }

  Future<List<Track>> search(String query, {int limit = 20}) async {
    if (!await ensureToken()) {
      return const [];
    }
    final data = await _get('/v1/search', {
      'q': query,
      'type': 'track',
      'limit': '$limit',
    });
    final tracks = (data?['tracks'] as Map<String, dynamic>?)?['items'] as List? ?? const [];
    return tracks.whereType<Map<String, dynamic>>().map(_toTrack).toList();
  }

  /// Плейлист: через API, если заданы ключи, иначе (и при любой ошибке) через публичный embed.
  Future<Playlist> playlist(String id) async {
    if (await ensureToken()) {
      try {
        return await _playlistApi(id);
      } catch (_) {}
    }
    return playlistViaEmbed(id);
  }

  /// Альбом: аналогично — без ключей через embed.
  Future<Playlist> album(String id) async {
    if (await ensureToken()) {
      try {
        return await _albumApi(id);
      } catch (_) {}
    }
    return playlistViaEmbed(id, kind: 'album');
  }

  Future<Playlist> _playlistApi(String id) async {
    final data = await _get('/v1/playlists/$id');
    if (data == null) throw StateError('Spotify: плейлист не найден');

    final tracks = <Track>[];
    var next = data['tracks'] as Map<String, dynamic>?;
    var guard = 0;

    while (next != null && guard++ < 20) {
      for (final item in (next['items'] as List? ?? const [])) {
        if (item is Map<String, dynamic> && item['track'] is Map<String, dynamic>) {
          tracks.add(_toTrack(item['track'] as Map<String, dynamic>));
        }
      }
      final nextUrl = next['next'] as String?;
      if (nextUrl == null) break;
      next = await _getAbsolute(nextUrl);
    }

    return Playlist(
      id: data['id'] as String? ?? id,
      title: data['name'] as String? ?? 'Плейлист',
      description: data['description'] as String? ?? '',
      imageUrl: _imageOf(data),
      tracks: tracks,
      ownerName: (data['owner'] as Map<String, dynamic>?)?['display_name'] as String?,
    );
  }

  Future<Playlist> _albumApi(String id) async {
    final data = await _get('/v1/albums/$id');
    if (data == null) throw StateError('Spotify: альбом не найден');
    final tracks = (data['tracks'] as Map<String, dynamic>?)?['items'] as List? ?? const [];
    final albumImage = _imageOf(data);
    final albumName = data['name'] as String? ?? 'Альбом';
    final artists = (data['artists'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((a) => a['name'] as String? ?? '')
        .join(', ');
    return Playlist(
      id: data['id'] as String? ?? id,
      title: albumName,
      imageUrl: albumImage,
      ownerName: artists,
      tracks: tracks
          .whereType<Map<String, dynamic>>()
          .map((t) => _toTrack(t, albumImage: albumImage, albumArtist: artists, albumName: albumName))
          .toList(),
    );
  }

  Future<Playlist> playlistViaEmbed(String id, {String kind = 'playlist'}) async {
    Object? error;
    final passes = <bool>[false, if (_proxy.hasWorker && !_proxy.enabled) true];
    for (final viaWorker in passes) {
      try {
        final response = await _dio.getUri<String>(
          _proxy.spotifyEmbed('/embed/$kind/$id', null, viaWorker),
          options: Options(
            responseType: ResponseType.plain,
            headers: {'user-agent': _browserUa, 'accept': 'text/html'},
          ),
        );
        return _parseEmbed(response.data ?? '', id, kind);
      } catch (e) {
        error = e;
      }
    }
    throw error ?? StateError('Spotify: embed недоступен');
  }

  Playlist _parseEmbed(String html, String id, [String kind = 'playlist']) {
    final match = RegExp(
      r'<script[^>]+id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      throw StateError('Spotify: не удалось разобрать эмбед');
    }
    final decoded = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final entity = _dig(decoded, ['props', 'pageProps', 'state', 'data', 'entity'])
        as Map<String, dynamic>?;
    if (entity == null) throw StateError('Spotify: эмбед без данных');

    final list = entity['trackList'] as List? ?? const [];
    final coverArt = entity['coverArt'];
    String? coverUrl;
    if (coverArt is Map<String, dynamic>) {
      final sources = coverArt['sources'];
      if (sources is List && sources.isNotEmpty) {
        final first = sources.first;
        if (first is Map<String, dynamic>) {
          coverUrl = first['url'] as String?;
        }
      }
    }

    return Playlist(
      id: entity['id'] as String? ?? id,
      title: entity['name'] as String? ??
          entity['title'] as String? ??
          'Плейлист Spotify',
      description: entity['subtitle'] as String? ?? '',
      imageUrl: coverUrl,
      ownerName: entity['subtitle'] as String?,
      tracks: list.whereType<Map<String, dynamic>>().map((item) {
        final uri = item['uri'] as String? ?? '';
        final trackId = uri.split(':').last;
        return Track(
          id: 'sp:$trackId',
          title: item['title'] as String? ?? 'Без названия',
          artist: item['subtitle'] as String? ?? 'Spotify',
          album: kind == 'album' ? (entity['name'] as String? ?? '') : '',
          duration: Duration(milliseconds: (item['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: coverUrl,
          source: TrackSource.spotify,
        );
      }).toList(),
    );
  }

  Future<Map<String, dynamic>?> _get(String path, [Map<String, dynamic>? query]) async {
    final response = await _dio.getUri<dynamic>(
      _proxy.spotifyApi(path, query),
      options: Options(
        headers: {'authorization': 'Bearer $_token'},
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getAbsolute(String url) async {
    final uri = Uri.parse(url);
    final path = uri.path;
    final query = uri.queryParameters.map((k, v) => MapEntry(k, v));
    final response = await _dio.getUri<dynamic>(
      _proxy.spotifyApi(path, query),
      options: Options(
        headers: {'authorization': 'Bearer $_token'},
        responseType: ResponseType.json,
      ),
    );
    final data = response.data;
    return data is Map<String, dynamic> ? data : null;
  }

  dynamic _dig(Map<String, dynamic> map, List<String> path) {
    dynamic current = map;
    for (final key in path) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _imageOf(Map<String, dynamic> json) {
    final images = (json['images'] as List?) ?? const [];
    if (images.isNotEmpty) {
      return (images.first as Map<String, dynamic>)['url'] as String?;
    }
    final album = json['album'] as Map<String, dynamic>?;
    if (album != null) return _imageOf(album);
    return null;
  }

  Track _toTrack(
    Map<String, dynamic> json, {
    String? albumImage,
    String? albumArtist,
    String? albumName,
  }) {
    final artists = (json['artists'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    final album = json['album'] as Map<String, dynamic>?;
    return Track(
      id: 'sp:${json['id'] as String? ?? ''}',
      title: json['name'] as String? ?? 'Без названия',
      artist: artists.isEmpty ? (albumArtist ?? 'Spotify') : artists,
      album: albumName ?? album?['name'] as String? ?? '',
      duration: Duration(milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0),
      thumbnailUrl: albumImage ?? _imageOf(json),
      explicit: json['explicit'] as bool? ?? false,
      source: TrackSource.spotify,
    );
  }

  String? spotifyId(String trackId) =>
      trackId.startsWith('sp:') ? trackId.substring(3) : null;
}
