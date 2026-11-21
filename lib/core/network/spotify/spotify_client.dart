import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../network/http_client.dart';
import '../../network/proxy.dart';
import '../../storage/settings.dart';

/// Spotify без пользовательского OAuth.
///
/// Стратегия:
/// 1. client id/secret (если указаны);
/// 2. анонимный токен веб-плеера (через Worker или напрямую);
/// 3. публичные embed-страницы и `__NEXT_DATA__` как источник метаданных.
class SpotifyClient {
  SpotifyClient({required Settings settings, required ProxyConfig proxy})
      : _settings = settings,
        _proxy = proxy,
        _dio = createDio(settings: settings, receiveTimeout: const Duration(seconds: 15));

  final Settings _settings;
  final ProxyConfig _proxy;
  final Dio _dio;

  String? _token;
  DateTime? _expiresAt;
  bool _apiBroken = false;

  bool get hasCredentials =>
      _settings.spotifyClientId.isNotEmpty && _settings.spotifyClientSecret.isNotEmpty;

  bool get guestMode => _settings.spotifyGuestMode || !hasCredentials;

  Future<bool> ensureToken() async => (await _accessToken()) != null;

  Future<String?> _accessToken({bool force = false}) async {
    if (!force) {
      final manual = _settings.spotifyAccessToken;
      if (manual.isNotEmpty) return manual;
      if (_token != null &&
          _expiresAt != null &&
          DateTime.now().isBefore(_expiresAt!.subtract(const Duration(seconds: 30)))) {
        return _token;
      }
    }

    final token = await _clientCredentialsToken() ?? await _anonymousToken();
    if (token == null) return null;
    _token = token;
    _apiBroken = false;
    return token;
  }

  Future<String?> _clientCredentialsToken() async {
    if (!hasCredentials) return null;
    try {
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
      return _readToken(response.data);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _anonymousToken() async {
    if (!guestMode) return null;

    if (_proxy.enabled) {
      try {
        final response = await _dio.getUri<dynamic>(_proxy.workerSpotifyToken);
        final token = _readToken(response.data is String
            ? jsonDecode(response.data as String) as dynamic
            : response.data);
        if (token != null) return token;
      } catch (_) {}
    }

    const paths = <String>[
      '/get_access_token?reason=transport&productType=web_player',
      '/api/token?reason=init&productType=web_player',
    ];

    for (final path in paths) {
      for (final uri in _embedCandidates(path)) {
        try {
          final response = await _dio.getUri<dynamic>(
            uri,
            options: Options(
              responseType: ResponseType.plain,
              receiveTimeout: const Duration(seconds: 6),
              headers: {
                ..._proxy.webHeaders,
                'accept': 'application/json, text/plain, */*',
              },
            ),
          );
          final body = response.data;
          dynamic decoded;
          if (body is String && body.trim().isNotEmpty) {
            decoded = jsonDecode(body);
          } else if (body is Map) {
            decoded = body;
          }
          final token = _readToken(decoded);
          if (token != null) return token;
        } catch (_) {}
      }
    }
    return null;
  }

  String? _readToken(dynamic data) {
    if (data is! Map) return null;
    final token = (data['accessToken'] ?? data['access_token'] ?? data['token']) as String?;
    if (token == null || token.isEmpty) return null;
    final rawSeconds = data['expiresIn'] ?? data['expires_in'];
    final seconds = rawSeconds is num ? rawSeconds.toInt() : 3600;
    final rawExpiresAt = data['expiresAt'] ?? data['expires_at'];
    final expiresAt = rawExpiresAt is num ? rawExpiresAt.toInt() : null;
    _expiresAt = expiresAt != null && expiresAt > 1000000000000
        ? DateTime.fromMillisecondsSinceEpoch(expiresAt)
        : DateTime.now().add(Duration(seconds: seconds));
    _apiBroken = false;
    return token;
  }

  Future<List<Track>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    if (!_apiBroken) {
      try {
        final data = await _get('/v1/search', {
          'q': trimmed,
          'type': 'track',
          'limit': '$limit',
          'market': 'RU',
        });
        final tracks =
            (data?['tracks'] as Map<String, dynamic>?)?['items'] as List? ?? const [];
        final parsed = tracks.whereType<Map<String, dynamic>>().map(_toTrack).toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {}
    }

    // Публичная страница поиска (без токена).
    final html = await _fetchHtml('/search/${Uri.encodeComponent(trimmed)}/tracks');
    if (html != null) {
      final tracks = _parsePublicTracks(html, limit: limit);
      if (tracks.isNotEmpty) return tracks;
    }
    return const [];
  }

  Future<Playlist> playlist(String id) async {
    if (!_apiBroken) {
      final data = await _get('/v1/playlists/$id');
      if (data != null) {
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
    }
    return playlistViaEmbed(id);
  }

  Future<Playlist> album(String id) async {
    if (!_apiBroken) {
      final data = await _get('/v1/albums/$id');
      if (data != null) {
        final tracks = (data['tracks'] as Map<String, dynamic>?)?['items'] as List? ?? const [];
        final albumImage = _imageOf(data);
        final albumName = data['name'] as String? ?? 'Альбом';
        final artists = (data['artists'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((a) => a['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ');
        return Playlist(
          id: data['id'] as String? ?? id,
          title: albumName,
          imageUrl: albumImage,
          ownerName: artists,
          tracks: tracks
              .whereType<Map<String, dynamic>>()
              .map((t) => _toTrack(
                    t,
                    albumImage: albumImage,
                    albumArtist: artists,
                    albumName: albumName,
                  ))
              .toList(),
        );
      }
    }
    return playlistViaEmbed(id, kind: 'album', fallbackTitle: 'Альбом');
  }

  Future<Track?> track(String id) async {
    final html = await _fetchHtml('/embed/track/$id');
    if (html == null) return null;
    final data = _nextData(html);
    if (data == null) return null;
    final entity = _findTrackEntity(data, id);
    if (entity == null) return null;
    return _trackFromNode(entity) ??
        Track(
          id: 'sp:$id',
          title: entity['name'] as String? ?? 'Трек',
          artist: 'Spotify',
          source: TrackSource.spotify,
        );
  }

  Future<Playlist> playlistViaEmbed(
    String id, {
    String kind = 'playlist',
    String fallbackTitle = 'Плейлист',
  }) async {
    final html = await _fetchHtml('/embed/$kind/$id');
    if (html == null) {
      throw StateError('Spotify: публичная страница недоступна');
    }
    return _parseEmbed(html, id, kind: kind, fallbackTitle: fallbackTitle);
  }

  Playlist _parseEmbed(
    String html,
    String id, {
    String kind = 'playlist',
    String fallbackTitle = 'Плейлист',
  }) {
    final data = _nextData(html);
    if (data == null) {
      throw StateError('Spotify: не удалось разобрать публичную страницу');
    }
    final entity = _dig(data, ['props', 'pageProps', 'state', 'data', 'entity'])
        as Map<String, dynamic>?;
    if (entity == null) throw StateError('Spotify: страница без данных');

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
          '$fallbackTitle Spotify',
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
          album: kind == 'album'
              ? (entity['name'] as String? ?? entity['title'] as String? ?? '')
              : '',
          duration: Duration(milliseconds: (item['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: coverUrl,
          source: TrackSource.spotify,
        );
      }).toList(),
    );
  }

  Future<String?> _fetchHtml(String path) async {
    for (final uri in _embedCandidates(path)) {
      try {
        final response = await _dio.getUri<String>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
            headers: _proxy.webHeaders,
          ),
        );
        final status = response.statusCode ?? 0;
        final body = response.data;
        if (status >= 200 && status < 400 && body != null && body.isNotEmpty) {
          return body;
        }
      } catch (_) {}
    }
    return null;
  }

  List<Uri> _embedCandidates(String path) {
    if (_proxy.enabled) {
      return [_proxy.spotifyEmbed(path), _proxy.directEmbed(path)];
    }
    final list = <Uri>[_proxy.directEmbed(path)];
    if (_proxy.hasWorker) {
      list.add(_proxy.spotifyEmbed(path, null, true));
    }
    return list;
  }

  dynamic _nextData(String html) {
    final match = RegExp(
      r'<script[^>]+id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match != null) {
      try {
        return jsonDecode(match.group(1)!);
      } catch (_) {}
    }
    // Иногда Spotify отдаёт initialState отдельным скриптом.
    final state = RegExp(
      r'<script[^>]+id="initial-state"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (state != null) {
      try {
        final raw = state.group(1)!.trim();
        final decoded = base64Decode(raw);
        return jsonDecode(utf8.decode(decoded));
      } catch (_) {}
    }
    return null;
  }

  List<Track> _parsePublicTracks(String html, {required int limit}) {
    final data = _nextData(html);
    if (data == null) return const [];
    final out = <Track>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (out.length >= limit) return;
      if (node is Map) {
        final track = _trackFromNode(node, seen: seen);
        if (track != null) out.add(track);
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
    return out;
  }

  Track? _trackFromNode(Map node, {Set<String>? seen}) {
    final rawName = node['name'] ?? node['title'];
    if (rawName is! String || rawName.trim().isEmpty) return null;
    final name = rawName;

    String? id;
    final uri = node['uri'];
    if (uri is String && uri.startsWith('spotify:track:')) {
      id = uri.split(':').last;
    } else if (node['type'] == 'track' && node['id'] is String) {
      id = node['id'] as String;
    }
    if (id == null || id.isEmpty || id == 'null') return null;
    if (seen != null && !seen.add(id)) return null;

    final artists = <String>[];
    final rawArtists = node['artists'];
    if (rawArtists is List) {
      for (final artist in rawArtists) {
        if (artist is Map && artist['name'] is String) {
          artists.add(artist['name'] as String);
        } else if (artist is String) {
          artists.add(artist);
        }
      }
    }
    final rawSubtitle = node['subtitle'];
    final subtitle = rawSubtitle is String ? rawSubtitle : null;
    final rawArtistName = node['artistName'];
    final artist = artists.isNotEmpty
        ? artists.join(', ')
        : (rawArtistName is String ? rawArtistName : (subtitle ?? 'Spotify'));

    final durationRaw = node['duration_ms'] ?? node['duration'];
    Duration duration = Duration.zero;
    if (durationRaw is num) {
      duration = Duration(
        milliseconds: durationRaw > 100000 ? durationRaw.toInt() : durationRaw.toInt() * 1000,
      );
    } else if (durationRaw is Map && durationRaw['totalMilliseconds'] is num) {
      duration = Duration(
        milliseconds: (durationRaw['totalMilliseconds'] as num).toInt(),
      );
    }

    final image = _imageOf(node);
    return Track(
      id: 'sp:$id',
      title: name,
      artist: artist,
      duration: duration,
      thumbnailUrl: image,
      source: TrackSource.spotify,
    );
  }

  Map<String, dynamic>? _findTrackEntity(dynamic node, String id) {
    if (node is Map<String, dynamic>) {
      final type = node['type'];
      final nodeId = node['id'];
      if (type == 'track' && nodeId == id && node['name'] is String) return node;
      for (final value in node.values) {
        final found = _findTrackEntity(value, id);
        if (found != null) return found;
      }
    } else if (node is Map) {
      for (final value in node.values) {
        final found = _findTrackEntity(value, id);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findTrackEntity(value, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final token = await _accessToken();
      var response = await _request(path, query, token);
      if ((response.statusCode == 401 || response.statusCode == 403) && token != null) {
        _token = null;
        final fresh = await _accessToken(force: true);
        response = await _request(path, query, fresh);
      }
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        if (status == 403 || status == 429) _apiBroken = true;
        return null;
      }
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Response<dynamic>> _request(
    String path,
    Map<String, dynamic>? query,
    String? token,
  ) {
    return _dio.getUri<dynamic>(
      _proxy.spotifyApi(path, query),
      options: Options(
        headers: {
          if (token != null) 'authorization': 'Bearer $token',
          'accept': 'application/json',
          'app-platform': 'WebPlayer',
          'spotify-app-version': '1.2.24.756.g7d9c1f8d',
        },
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Map<String, dynamic>?> _getAbsolute(String url) async {
    final uri = Uri.parse(url);
    return _get(uri.path, uri.queryParameters.map((k, v) => MapEntry(k, v)));
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

  String? _imageOf(Map<dynamic, dynamic> json) {
    final album = json['album'];
    if (album is Map) {
      final inner = _imageOf(album);
      if (inner != null) return inner;
    }
    final images = json['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) return first['url'] as String?;
      if (first is String) return first;
    }
    final coverArt = json['coverArt'];
    if (coverArt is Map) {
      final sources = coverArt['sources'];
      if (sources is List && sources.isNotEmpty) {
        final first = sources.first;
        if (first is Map) return first['url'] as String?;
      }
    }
    final albumOfTrack = json['albumOfTrack'];
    if (albumOfTrack is Map) return _imageOf(albumOfTrack);
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
