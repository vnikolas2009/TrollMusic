import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/settings.dart';
import 'mirror_manager.dart';

/// Актуальные списки публичных Piped/Invidious-инстансов.
///
/// Встроенный список устаревает, поэтому раз в сутки приложение само скачивает
/// свежие каталоги инстансов и сохраняет их локально. Пользователю ничего
/// настраивать не нужно; если каталог недоступен, работают встроенные адреса.
class InstanceDirectory {
  InstanceDirectory._();

  static final InstanceDirectory instance = InstanceDirectory._();

  static const _maxAge = Duration(hours: 24);
  static const _maxFresh = 8;

  Settings? _settings;
  Dio? _dio;
  bool _refreshing = false;

  void attach(Settings settings, Dio dio) {
    _settings = settings;
    _dio = dio;
  }

  List<String> list(MirrorKind kind) {
    final fresh = kind == MirrorKind.piped
        ? _settings?.cachedPiped ?? const <String>[]
        : _settings?.cachedInvidious ?? const <String>[];
    final defaults = kind == MirrorKind.piped
        ? AppConfig.defaultPipedInstances
        : AppConfig.defaultInvidiousInstances;
    final seen = <String>{};
    return [
      for (final origin in [...fresh, ...defaults])
        if (seen.add(_normalize(origin))) _normalize(origin),
    ];
  }

  Future<void> refreshIfStale() async {
    final updated = _settings?.directoryUpdatedAt;
    if (updated != null && DateTime.now().difference(updated) < _maxAge) return;
    await refresh();
  }

  Future<void> refresh() async {
    final settings = _settings;
    final dio = _dio;
    if (settings == null || dio == null || _refreshing) return;
    _refreshing = true;
    try {
      final results = await Future.wait([
        _fetchPiped(dio),
        _fetchInvidious(dio),
      ]);
      var changed = false;
      if (results[0].isNotEmpty) {
        settings.cachedPiped = results[0];
        changed = true;
      }
      if (results[1].isNotEmpty) {
        settings.cachedInvidious = results[1];
        changed = true;
      }
      if (changed) settings.directoryUpdatedAt = DateTime.now();
    } catch (_) {
      // Каталог недоступен — остаёмся на сохранённых и встроенных адресах.
    } finally {
      _refreshing = false;
    }
  }

  Future<List<String>> _fetchPiped(Dio dio) async {
    try {
      final response = await dio.get<dynamic>(
        AppConfig.pipedDirectoryUrl,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final data = response.data;
      if (data is! List) return const [];
      final items = <({String url, double uptime})>[];
      for (final raw in data) {
        if (raw is! Map) continue;
        final url = raw['api_url'];
        if (url is! String || !url.startsWith('http')) continue;
        final uptime = (raw['uptime_24h'] as num?)?.toDouble() ??
            (raw['uptime_30d'] as num?)?.toDouble() ??
            0;
        items.add((url: url, uptime: uptime));
      }
      items.sort((a, b) => b.uptime.compareTo(a.uptime));
      return [for (final item in items.take(_maxFresh)) item.url];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _fetchInvidious(Dio dio) async {
    try {
      final response = await dio.get<dynamic>(
        AppConfig.invidiousDirectoryUrl,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final data = response.data;
      if (data is! List) return const [];
      final urls = <String>[];
      for (final raw in data) {
        if (raw is! List || raw.length < 2) continue;
        final info = raw[1];
        if (info is! Map) continue;
        if (info['type'] != 'https' || info['api'] != true) continue;
        final uri = info['uri'];
        if (uri is String && uri.startsWith('http')) urls.add(uri);
        if (urls.length >= _maxFresh) break;
      }
      return urls;
    } catch (_) {
      return const [];
    }
  }

  String _normalize(String origin) {
    var value = origin.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
