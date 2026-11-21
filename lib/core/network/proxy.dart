import '../storage/settings.dart';

class ProxyConfig {
  ProxyConfig(this._settings);

  final Settings _settings;

  String get workerUrl {
    final raw = _settings.workerUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// Worker вообще указан (годится как запасной путь).
  bool get hasWorker => workerUrl.isNotEmpty;

  /// Worker используется всегда, а не только как запасной путь.
  bool get enabled => _settings.useWorkerProxy && hasWorker;

  Uri spotifyApi(String path, [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _build('spotify', path, query, viaWorker);

  Uri spotifyAccounts(String path, [bool viaWorker = false]) =>
      _build('accounts', path, null, viaWorker);

  Uri spotifyCdn(String path) => _build('cdn', path);

  Uri spotifyEmbed(String path, [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _build('embed', path, query, viaWorker);

  /// Прямой адрес open.spotify.com в обход Worker.
  Uri directEmbed(String path, [Map<String, dynamic>? query]) =>
      _direct('https://open.spotify.com', path, query);

  /// Анонимный токен, который раздаёт Worker (если развёрнут).
  Uri get workerSpotifyToken => Uri.parse('$workerUrl/token');

  Uri piped(String origin, String path,
          [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _mirror('piped', origin, path, query, viaWorker);

  Uri invidious(String origin, String path,
          [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _mirror('invidious', origin, path, query, viaWorker);

  Uri passthrough(String url) => Uri.parse('$workerUrl/proxy').replace(
        queryParameters: {'url': url},
      );

  /// Заголовки для запросов к публичному веб-плееру Spotify.
  Map<String, String> get webHeaders => {
        'user-agent': _settings.requestHeaders['user-agent'] ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'accept': 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
        'accept-language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
        'app-platform': 'WebPlayer',
        'referer': 'https://open.spotify.com/',
        'origin': 'https://open.spotify.com',
        ..._settings.requestHeaders,
      };

  Uri media(String url) {
    if (!enabled) return Uri.parse(url);
    if (_isWorkerHosted(url)) return Uri.parse(url);
    return passthrough(url);
  }

  Uri artwork(String? url, {String? fallback}) {
    if (url == null || url.isEmpty) return Uri.parse(fallback ?? '');
    if (url.startsWith('https://i.scdn.co')) {
      return enabled ? spotifyCdn(url.substring('https://i.scdn.co'.length)) : Uri.parse(url);
    }
    return media(url);
  }

  /// Если [url] — ссылка через `/proxy?url=...`, возвращает оригинальный адрес.
  String? unwrap(String url) {
    if (!enabled) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (!url.startsWith(workerUrl)) return null;
    return uri.queryParameters['url'];
  }

  Uri _mirror(String prefix, String origin, String path,
      Map<String, dynamic>? query, bool viaWorker) {
    if ((enabled || viaWorker) && hasWorker) {
      return _build(prefix, '${_host(origin)}$path', query, true);
    }
    final base = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final clean = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$clean').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Uri _direct(String origin, String path, [Map<String, dynamic>? query]) {
    final root = origin.endsWith('/') ? origin.substring(0, origin.length - 1) : origin;
    final clean = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$root$clean');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: query.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Uri _build(String prefix, String path,
      [Map<String, dynamic>? query, bool viaWorker = false]) {
    final useWorker = (enabled || viaWorker) && hasWorker;
    final base = useWorker ? '$workerUrl/$prefix' : _directBase(prefix);
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$base/$clean');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: query.map((k, v) => MapEntry(k, '$v')),
    );
  }

  String _directBase(String prefix) => switch (prefix) {
        'spotify' => 'https://api.spotify.com',
        'accounts' => 'https://accounts.spotify.com',
        'cdn' => 'https://i.scdn.co',
        'embed' => 'https://open.spotify.com',
        _ => throw ArgumentError('unsupported prefix $prefix'),
      };

  bool _isWorkerHosted(String url) => enabled && url.startsWith(workerUrl);

  String _host(String origin) {
    final uri = Uri.parse(origin);
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}
