import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/settings.dart';
import '../utils/async_utils.dart';
import 'instance_directory.dart';
import 'proxy.dart';
import 'worker_health.dart';

enum MirrorKind { piped, invidious }

class MirrorManager {
  MirrorManager({
    required Settings settings,
    required Dio dio,
    WorkerHealth? health,
  })  : _settings = settings,
        _dio = dio,
        _health = health,
        _proxy = ProxyConfig(settings);

  final Settings _settings;
  final Dio _dio;
  final ProxyConfig _proxy;
  final WorkerHealth? _health;
  final Map<MirrorKind, String?> _sticky = {};
  final Map<String, DateTime> _failed = {};

  /// Список зеркал: свежие из встроенного каталога + запасные из AppConfig.
  /// Пользовательские списки больше не используются — всё работает без настройки.
  List<String> instancesOf(MirrorKind kind) =>
      InstanceDirectory.instance.list(kind);

  static const _waveSize = 3;
  static const _maxWaves = 3;

  /// Запрашивает зеркала «волнами» по три параллельно: побеждает первое,
  /// остальные запросы отменяются. Раньше зеркала перебирались по одному
  /// (до 4 с на каждое), и разрешение трека могло занимать больше минуты.
  Future<Response<dynamic>> get(
    MirrorKind kind,
    String path, {
    Map<String, dynamic>? query,
    Duration timeout = AppConfig.mirrorTimeout,
  }) async {
    final instances = instancesOf(kind);
    if (instances.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        message: 'Список зеркал пуст',
      );
    }

    var ordered = _order(kind, instances).where((o) => !_isCoolingDown(o)).toList();
    if (ordered.isEmpty) {
      _failed.clear();
      ordered = _order(kind, instances);
    }

    _lastError = null;
    for (var wave = 0; wave < _maxWaves; wave++) {
      final batch = ordered.skip(wave * _waveSize).take(_waveSize).toList();
      if (batch.isEmpty) break;
      final cancel = CancelToken();
      final response = await firstNonEmpty<Response<dynamic>>([
        for (final origin in batch)
          () => _attempt(kind, origin, path, query, timeout, cancel, false),
      ]);
      cancel.cancel('wave finished');
      if (response != null) return response;
    }

    // Запасной путь через пользовательский Worker, если он когда-то был задан.
    if (_proxy.hasWorker && !_proxy.enabled && (_health?.usable ?? true)) {
      final cancel = CancelToken();
      final response = await firstNonEmpty<Response<dynamic>>([
        for (final origin in ordered.take(2))
          () => _attempt(kind, origin, path, query, timeout, cancel, true),
      ]);
      cancel.cancel('worker pass finished');
      if (response != null) return response;
    }

    throw DioException(
      requestOptions: RequestOptions(path: path),
      message: 'Все зеркала ${kind.name} недоступны: $_lastError',
    );
  }

  Object? _lastError;

  Future<Response<dynamic>?> _attempt(
    MirrorKind kind,
    String origin,
    String path,
    Map<String, dynamic>? query,
    Duration timeout,
    CancelToken cancel,
    bool viaWorker,
  ) async {
    try {
      final uri = kind == MirrorKind.piped
          ? _proxy.piped(origin, path, query, viaWorker)
          : _proxy.invidious(origin, path, query, viaWorker);
      final response = await _dio
          .getUri<dynamic>(uri, cancelToken: cancel)
          .timeout(
            timeout,
            onTimeout: () => throw DioException(
              requestOptions: RequestOptions(path: uri.toString()),
              type: DioExceptionType.connectionTimeout,
            ),
          );
      if (response.statusCode == 200 && response.data != null) {
        _sticky[kind] = origin;
        _failed.remove(origin);
        return response;
      }
      _lastError = 'HTTP ${response.statusCode}';
      if (!viaWorker) _failed[origin] = DateTime.now();
      return null;
    } catch (error) {
      if (error is DioException && CancelToken.isCancel(error)) return null;
      _lastError = error;
      if (!viaWorker) _failed[origin] = DateTime.now();
      return null;
    }
  }

  List<String> _order(MirrorKind kind, List<String> instances) {
    final sticky = _sticky[kind];
    if (sticky == null || !instances.contains(sticky)) return instances;
    return [sticky, ...instances.where((i) => i != sticky)];
  }

  bool _isCoolingDown(String origin) {
    final failedAt = _failed[origin];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) < const Duration(minutes: 2);
  }

  void resetHealth() {
    _failed.clear();
    _sticky.clear();
  }

  Future<MirrorProbe> probe(MirrorKind kind, String origin) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = kind == MirrorKind.piped
          ? _proxy.piped(origin, '/trending', {'region': 'RU'})
          : _proxy.invidious(origin, '/api/v1/trending', {'region': 'RU'});
      final response = await _dio.getUri<dynamic>(uri).timeout(
            AppConfig.mirrorTimeout,
            onTimeout: () => throw DioException(
              requestOptions: RequestOptions(path: uri.toString()),
              type: DioExceptionType.connectionTimeout,
            ),
          );
      stopwatch.stop();
      final ok = response.statusCode == 200 && response.data != null;
      if (ok) {
        _failed.remove(origin);
      } else {
        _failed[origin] = DateTime.now();
      }
      return MirrorProbe(
        origin: origin,
        ok: ok,
        latency: stopwatch.elapsedMilliseconds,
        detail: ok ? null : 'HTTP ${response.statusCode}',
      );
    } catch (error) {
      stopwatch.stop();
      _failed[origin] = DateTime.now();
      return MirrorProbe(
        origin: origin,
        ok: false,
        latency: stopwatch.elapsedMilliseconds,
        detail: error is DioException ? error.type.name : error.toString(),
      );
    }
  }

  Future<List<MirrorProbe>> probeAll(MirrorKind kind) async {
    final instances = instancesOf(kind);
    return Future.wait(instances.map((origin) => probe(kind, origin)));
  }
}

class MirrorProbe {
  const MirrorProbe({
    required this.origin,
    required this.ok,
    required this.latency,
    this.detail,
  });

  final String origin;
  final bool ok;
  final int latency;
  final String? detail;
}
