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

  Uri piped(String origin, String path,
          [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _mirror('piped', origin, path, query, viaWorker);

  Uri invidious(String origin, String path,
          [Map<String, dynamic>? query, bool viaWorker = false]) =>
      _mirror('invidious', origin, path, query, viaWorker);

  Uri passthrough(String url) => Uri.parse('$workerUrl/proxy').replace(
        queryParameters: {'url': url},
      );

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

  Uri _build(String prefix, String path,
      [Map<String, dynamic>? query, bool viaWorker = false]) {
    final useWorker = (enabled || viaWorker) && hasWorker;
    final base = useWorker ? '$workerUrl/$prefix' : _directBase(prefix);
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/$clean').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
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
