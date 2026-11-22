import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../config/app_config.dart';
import '../../network/http_client.dart';
import '../../storage/settings.dart';

/// Spotify metadata client.
///
/// Получает метаданные, поиск и плейлисты.
/// Не предоставляет прямые аудиопотоки Spotify.
class SpotifyClient {
  SpotifyClient({
    required Settings settings,
  })  : _settings = settings,
        _dio = createDio(
          settings: settings,
          receiveTimeout: const Duration(seconds: 15),
        );

  final Settings _settings;
  final Dio _dio;

  static const _webHeaders = <String, String>{
    'user-agent': AppConfig.spotifyWebUserAgent,
    'accept-language':
        'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'referer': 'https://open.spotify.com/',
  };

  static final _webBase = Uri.parse(
    'https://open.spotify.com',
  );

  Uri _apiUri(
    String path, [
    Map<String, dynamic>? query,
  ]) {
    return Uri(
      scheme: 'https',
      host: 'api.spotify.com',
      path: path,
      queryParameters: query?.map(
        (key, value) => MapEntry(key, '$value'),
      ),
    );
  }

  Uri _backendUri(
    String path, [
    Map<String, String>? query,
  ]) {
    final base = Uri.parse(_settings.apiBaseUrl);

    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    return base.replace(
      path: '$basePath$path',
      queryParameters: query,
    );
  }

  String? _token;
  DateTime? _expiresAt;

  bool _apiBroken = false;

  bool get hasCredentials =>
      _settings.spotifyClientId.isNotEmpty &&
      _settings.spotifyClientSecret.isNotEmpty;

  bool get guestMode =>
      _settings.spotifyGuestMode || !hasCredentials;

  Future<bool> ensureToken() async {
    return (await _accessToken()) != null;
  }

  Future<String?> _accessToken({
    bool force = false,
  }) async {
    if (!force) {
      final manual = _settings.spotifyAccessToken;

      if (manual.isNotEmpty) return manual;

      if (_token != null &&
          _expiresAt != null &&
          DateTime.now().isBefore(
            _expiresAt!.subtract(
              const Duration(seconds: 30),
            ),
          )) {
        return _token;
      }
    }

    final token =
        await _clientCredentialsToken() ??
        await _anonymousToken();

    if (token == null) return null;

    _token = token;
    _apiBroken = false;

    return token;
  }

  Future<String?> _clientCredentialsToken() async {
    if (!hasCredentials) return null;

    try {
      final basic = base64Encode(
        utf8.encode(
          '${_settings.spotifyClientId}:'
          '${_settings.spotifyClientSecret}',
        ),
      );

      final response = await _dio.postUri<Map<String, dynamic>>(
        Uri.parse(
          'https://accounts.spotify.com/api/token',
        ),
        data: 'grant_type=client_credentials',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {
            'authorization': 'Basic $basic',
          },
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

    // 1. Собственный backend.
    final backend = await _getJson(
      _backendUri('/api/spotify/token'),
    );

    final backendToken = _readToken(backend);

    if (backendToken != null) {
      return backendToken;
    }

    // 2. Публичный Web Player.
    const paths = <String>[
      '/get_access_token?reason=transport&productType=web_player',
      '/api/token?reason=init&productType=web_player',
    ];

    for (final path in paths) {
      final decoded = await _getJson(
        _webUri(path),
        headers: _webHeaders,
      );

      final token = _readToken(decoded);

      if (token != null) return token;
    }

    return null;
  }

  Future<dynamic> _getJson(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            ...?headers,
            'accept': 'application/json, text/plain, */*',
          },
        ),
      );

      final status = response.statusCode ?? 0;

      if (status < 200 || status >= 300) {
        return null;
      }

      final body = response.data;

      if (body is String && body.trim().isNotEmpty) {
        return jsonDecode(body);
      }

      if (body is Map) return body;

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Импорт публичного плейлиста, альбома или трека
  /// через собственный Vercel backend.
  Future<Playlist?> _backendImport(
    String type,
    String id,
  ) async {
    try {
      final data = await _getJson(
        _backendUri(
          '/api/spotify/import',
          {
            'type': type,
            'id': id,
          },
        ),
      );

      if (data is! Map) return null;

      final rawTracks = data['tracks'];

      if (rawTracks is! List || rawTracks.isEmpty) {
        return null;
      }

      final cover = data['cover'] as String?;

      final tracks = <Track>[
        for (final item in rawTracks)
          if (item is Map &&
              item['id'] is String &&
              item['title'] is String)
            Track(
              id: 'sp:${item['id']}',
              title: item['title'] as String,
              artist:
                  (item['artist'] as String?)?.trim().isNotEmpty == true
                      ? item['artist'] as String
                      : 'Spotify',
              album: type == 'album'
                  ? (data['title'] as String? ?? '')
                  : '',
              duration: Duration(
                milliseconds:
                    (item['durationMs'] as num?)?.toInt() ?? 0,
              ),
              thumbnailUrl:
                  item['cover'] as String? ?? cover,
              source: TrackSource.spotify,
            ),
      ];

      if (tracks.isEmpty) return null;

      return Playlist(
        id: data['id'] as String? ?? id,
        title: data['title'] as String? ??
            (type == 'album' ? 'Альбом' : 'Плейлист'),
        imageUrl: cover,
        tracks: tracks,
      );
    } catch (_) {
      return null;
    }
  }

  String? _readToken(dynamic data) {
    if (data is! Map) return null;

    final rawToken = data['accessToken'] ??
        data['access_token'] ??
        data['token'];

    if (rawToken is! String || rawToken.isEmpty) {
      return null;
    }

    final rawSeconds =
        data['expiresIn'] ?? data['expires_in'];

    final seconds = rawSeconds is num
        ? rawSeconds.toInt()
        : 3600;

    final rawExpiresAt =
        data['expiresAt'] ?? data['expires_at'];

    final expiresAt = rawExpiresAt is num
        ? rawExpiresAt.toInt()
        : null;

    _expiresAt = expiresAt != null &&
            expiresAt > 1000000000000
        ? DateTime.fromMillisecondsSinceEpoch(
            expiresAt,
          )
        : DateTime.now().add(
            Duration(seconds: seconds),
          );

    _apiBroken = false;

    return rawToken;
  }

  /// Поиск треков Spotify.
  Future<List<Track>> search(
    String query, {
    int limit = 20,
  }) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return const [];

    if (!_apiBroken) {
      try {
        final data = await _get(
          '/v1/search',
          {
            'q': trimmed,
            'type': 'track',
            'limit': limit.clamp(1, 50),
          },
        );

        final tracks =
            (data?['tracks'] as Map<String, dynamic>?)
                    ?['items'] as List? ??
                const [];

        final parsed = tracks
            .whereType<Map<String, dynamic>>()
            .map(_toTrack)
            .toList();

        if (parsed.isNotEmpty) return parsed;
      } catch (_) {}
    }

    // Резервный поиск по публичной странице.
    final html = await _fetchHtml(
      '/search/${Uri.encodeComponent(trimmed)}/tracks',
    );

    if (html != null) {
      final tracks = _parsePublicTracks(
        html,
        limit: limit,
      );

      if (tracks.isNotEmpty) return tracks;
    }

    return const [];
  }

  /// Импорт плейлиста.
  Future<Playlist> playlist(String id) async {
    final imported = await _backendImport(
      'playlist',
      id,
    );

    if (imported != null) return imported;

    if (!_apiBroken) {
      final data = await _get('/v1/playlists/$id');

      if (data != null) {
        final tracks = <Track>[];

        var next =
            data['tracks'] as Map<String, dynamic>?;

        var guard = 0;

        while (next != null && guard++ < 20) {
          final items =
              next['items'] as List? ?? const [];

          for (final item in items) {
            if (item is Map<String, dynamic> &&
                item['track'] is Map<String, dynamic>) {
              tracks.add(
                _toTrack(
                  item['track'] as Map<String, dynamic>,
                ),
              );
            }
          }

          final nextUrl = next['next'] as String?;

          if (nextUrl == null) break;

          next = await _getAbsolute(nextUrl);
        }

        return Playlist(
          id: data['id'] as String? ?? id,
          title: data['name'] as String? ?? 'Плейлист',
          description:
              data['description'] as String? ?? '',
          imageUrl: _imageOf(data),
          tracks: tracks,
          ownerName:
              (data['owner'] as Map<String, dynamic>?)
                  ?['display_name'] as String?,
        );
      }
    }

    return playlistViaEmbed(id);
  }

  /// Импорт альбома.
  Future<Playlist> album(String id) async {
    final imported = await _backendImport(
      'album',
      id,
    );

    if (imported != null) return imported;

    if (!_apiBroken) {
      final data = await _get('/v1/albums/$id');

      if (data != null) {
        final tracks =
            (data['tracks'] as Map<String, dynamic>?)
                    ?['items'] as List? ??
                const [];

        final albumImage = _imageOf(data);

        final albumName =
            data['name'] as String? ?? 'Альбом';

        final artists = (data['artists'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((a) => a['name'] as String? ?? '')
            .where((name) => name.isNotEmpty)
            .join(', ');

        return Playlist(
          id: data['id'] as String? ?? id,
          title: albumName,
          imageUrl: albumImage,
          ownerName: artists,
          tracks: tracks
              .whereType<Map<String, dynamic>>()
              .map(
                (track) => _toTrack(
                  track,
                  albumImage: albumImage,
                  albumArtist: artists,
                  albumName: albumName,
                ),
              )
              .toList(),
        );
      }
    }

    return playlistViaEmbed(
      id,
      kind: 'album',
      fallbackTitle: 'Альбом',
    );
  }

  /// Получение отдельного трека.
  Future<Track?> track(String id) async {
    final imported = await _backendImport(
      'track',
      id,
    );

    if (imported != null && imported.tracks.isNotEmpty) {
      return imported.tracks.first;
    }

    final html = await _fetchHtml(
      '/embed/track/$id',
    );

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
    final html = await _fetchHtml(
      '/embed/$kind/$id',
    );

    if (html == null) {
      throw StateError(
        'Spotify: публичная страница недоступна',
      );
    }

    return _parseEmbed(
      html,
      id,
      kind: kind,
      fallbackTitle: fallbackTitle,
    );
  }

  Playlist _parseEmbed(
    String html,
    String id, {
    String kind = 'playlist',
    String fallbackTitle = 'Плейлист',
  }) {
    final data = _nextData(html);

    if (data == null) {
      throw StateError(
        'Spotify: не удалось разобрать страницу',
      );
    }

    final entity = _dig(
      data,
      [
        'props',
        'pageProps',
        'state',
        'data',
        'entity',
      ],
    ) as Map<String, dynamic>?;

    if (entity == null) {
      throw StateError(
        'Spotify: страница без данных',
      );
    }

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
      description:
          entity['subtitle'] as String? ?? '',
      imageUrl: coverUrl,
      ownerName: entity['subtitle'] as String?,
      tracks: list
          .whereType<Map<String, dynamic>>()
          .map((item) {
        final uri = item['uri'] as String? ?? '';

        final trackId = uri.split(':').last;

        return Track(
          id: 'sp:$trackId',
          title: item['title'] as String? ?? 'Без названия',
          artist: item['subtitle'] as String? ?? 'Spotify',
          album: kind == 'album'
              ? (entity['name'] as String? ??
                  entity['title'] as String? ??
                  '')
              : '',
          duration: Duration(
            milliseconds:
                (item['duration'] as num?)?.toInt() ?? 0,
          ),
          thumbnailUrl: coverUrl,
          source: TrackSource.spotify,
        );
      }).toList(),
    );
  }

  Future<String?> _fetchHtml(String path) async {
    try {
      final response = await _dio.getUri<String>(
        _webUri(path),
        options: Options(
          responseType: ResponseType.plain,
          headers: _webHeaders,
        ),
      );

      final status = response.statusCode ?? 0;

      final body = response.data;

      if (status >= 200 &&
          status < 400 &&
          body != null &&
          body.isNotEmpty) {
        return body;
      }
    } catch (_) {}

    return null;
  }

  Uri _webUri(String path) {
    return Uri.parse(
      '${_webBase.origin}$path',
    );
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

    final state = RegExp(
      r'<script[^>]+id="initial-state"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);

    if (state != null) {
      try {
        final raw = state.group(1)!.trim();

        final decoded = base64Decode(raw);

        return jsonDecode(
          utf8.decode(decoded),
        );
      } catch (_) {}
    }

    return null;
  }

  List<Track> _parsePublicTracks(
    String html, {
    required int limit,
  }) {
    final data = _nextData(html);

    if (data == null) return const [];

    final out = <Track>[];

    final seen = <String>{};

    void walk(dynamic node) {
      if (out.length >= limit) return;

      if (node is Map) {
        final track = _trackFromNode(
          node,
          seen: seen,
        );

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

  Track? _trackFromNode(
    Map node, {
    Set<String>? seen,
  }) {
    final rawName = node['name'] ?? node['title'];

    if (rawName is! String || rawName.trim().isEmpty) {
      return null;
    }

    final name = rawName;

    String? id;

    final uri = node['uri'];

    if (uri is String &&
        uri.startsWith('spotify:track:')) {
      id = uri.split(':').last;
    } else if (node['type'] == 'track' &&
        node['id'] is String) {
      id = node['id'] as String;
    }

    if (id == null || id.isEmpty || id == 'null') {
      return null;
    }

    if (seen != null && !seen.add(id)) {
      return null;
    }

    final artists = <String>[];

    final rawArtists = node['artists'];

    if (rawArtists is List) {
      for (final artist in rawArtists) {
        if (artist is Map &&
            artist['name'] is String) {
          artists.add(artist['name'] as String);
        } else if (artist is String) {
          artists.add(artist);
        }
      }
    }

    final subtitle = node['subtitle'] is String
        ? node['subtitle'] as String
        : null;

    final artistName = node['artistName'];

    final artist = artists.isNotEmpty
        ? artists.join(', ')
        : (artistName is String
            ? artistName
            : (subtitle ?? 'Spotify'));

    final durationRaw =
        node['duration_ms'] ?? node['duration'];

    Duration duration = Duration.zero;

    if (durationRaw is num) {
      duration = Duration(
        milliseconds: durationRaw > 100000
            ? durationRaw.toInt()
            : durationRaw.toInt() * 1000,
      );
    } else if (durationRaw is Map &&
        durationRaw['totalMilliseconds'] is num) {
      duration = Duration(
        milliseconds:
            (durationRaw['totalMilliseconds'] as num).toInt(),
      );
    }

    return Track(
      id: 'sp:$id',
      title: name,
      artist: artist,
      duration: duration,
      thumbnailUrl: _imageOf(node),
      source: TrackSource.spotify,
    );
  }

  Map<String, dynamic>? _findTrackEntity(
    dynamic node,
    String id,
  ) {
    if (node is Map) {
      if (node['type'] == 'track' &&
          node['id'] == id &&
          node['name'] is String) {
        return Map<String, dynamic>.from(node);
      }

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

  Future<Map<String, dynamic>?> _get(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final token = await _accessToken();

      var response = await _request(
        path,
        query,
        token,
      );

      if ((response.statusCode == 401 ||
              response.statusCode == 403) &&
          token != null) {
        _token = null;
        _expiresAt = null;

        final fresh = await _accessToken(
          force: true,
        );

        response = await _request(
          path,
          query,
          fresh,
        );
      }

      final status = response.statusCode ?? 0;

      if (status < 200 || status >= 300) {
        if (status == 403 || status == 429) {
          _apiBroken = true;
        }

        return null;
      }

      final data = response.data;

      if (data is Map<String, dynamic>) {
        return data;
      }

      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);

        return decoded is Map<String, dynamic>
            ? decoded
            : null;
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
      _apiUri(path, query),
      options: Options(
        headers: {
          if (token != null)
            'authorization': 'Bearer $token',
          'accept': 'application/json',
          'app-platform': 'WebPlayer',
          'spotify-app-version': '1.2.24.756.g7d9c1f8d',
        },
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Map<String, dynamic>?> _getAbsolute(
    String url,
  ) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        uri.host != 'api.spotify.com') {
      return null;
    }

    return _get(
      uri.path,
      uri.queryParameters.map(
        (key, value) => MapEntry(key, value),
      ),
    );
  }

  dynamic _dig(
    Map<String, dynamic> map,
    List<String> path,
  ) {
    dynamic current = map;

    for (final key in path) {
      if (current is Map &&
          current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }

    return current;
  }

  String? _imageOf(
    Map<dynamic, dynamic> json,
  ) {
    final album = json['album'];

    if (album is Map) {
      final inner = _imageOf(album);

      if (inner != null) return inner;
    }

    final images = json['images'];

    if (images is List && images.isNotEmpty) {
      final first = images.first;

      if (first is Map) {
        return first['url'] as String?;
      }

      if (first is String) return first;
    }

    final coverArt = json['coverArt'];

    if (coverArt is Map) {
      final sources = coverArt['sources'];

      if (sources is List && sources.isNotEmpty) {
        final first = sources.first;

        if (first is Map) {
          return first['url'] as String?;
        }
      }
    }

    final albumOfTrack = json['albumOfTrack'];

    if (albumOfTrack is Map) {
      return _imageOf(albumOfTrack);
    }

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
        .where((name) => name.isNotEmpty)
        .join(', ');

    final album =
        json['album'] as Map<String, dynamic>?;

    return Track(
      id: 'sp:${json['id'] as String? ?? ''}',
      title: json['name'] as String? ?? 'Без названия',
      artist: artists.isEmpty
          ? (albumArtist ?? 'Spotify')
          : artists,
      album: albumName ??
          album?['name'] as String? ??
          '',
      duration: Duration(
        milliseconds:
            (json['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      thumbnailUrl:
          albumImage ?? _imageOf(json),
      explicit: json['explicit'] as bool? ?? false,
      source: TrackSource.spotify,
    );
  }

  String? spotifyId(String trackId) {
    return trackId.startsWith('sp:')
        ? trackId.substring(3)
        : null;
  }
}