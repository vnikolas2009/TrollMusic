import '../storage/settings.dart';

class ProxyConfig {
  ProxyConfig(this._settings);

  final Settings _settings;

  String get workerUrl {
    final raw = _settings.workerUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  bool get enabled => _settings.useWorkerProxy && workerUrl.isNotEmpty;

  Uri spotifyApi(String path, [Map<String, dynamic>? query]) =>
      _build('spotify', path, query);

  Uri spotifyAccounts(String path) => _build('accounts', path);

  Uri spotifyCdn(String path) => _build('cdn', path);

  Uri spotifyEmbed(String path, [Map<String, dynamic>? query]) =>
      _build('embed', path, query);

  Uri piped(String origin, String path, [Map<String, dynamic>? query]) =>
      _build('piped', '${_host(origin)}$path', query);

  Uri invidious(String origin, String path, [Map<String, dynamic>? query]) =>
      _build('invidious', '${_host(origin)}$path', query);

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

  Uri _build(String prefix, String path, [Map<String, dynamic>? query]) {
    final base = enabled ? '$workerUrl/$prefix' : _directBase(prefix);
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

  bool _isWorkerHosted(String url) =>
      enabled && url.startsWith(workerUrl);

  String _host(String origin) {
    final uri = Uri.parse(origin);
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }
}
