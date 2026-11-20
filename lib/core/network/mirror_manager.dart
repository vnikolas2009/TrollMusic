import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/settings.dart';
import 'proxy.dart';

enum MirrorKind { piped, invidious }

class MirrorManager {
  MirrorManager({required Settings settings, required Dio dio})
      : _settings = settings,
        _dio = dio,
        _proxy = ProxyConfig(settings);

  final Settings _settings;
  final Dio _dio;
  final ProxyConfig _proxy;
  final Map<MirrorKind, String?> _sticky = {};
  final Map<String, DateTime> _failed = {};

  List<String> instancesOf(MirrorKind kind) => kind == MirrorKind.piped
      ? _settings.pipedInstances
      : _settings.invidiousInstances;

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

    final ordered = _order(kind, instances);
    Object? lastError;

    // Сначала обычный путь, затем (если указан Worker) — запасной через Worker.
    final passes = <bool>[false, if (_proxy.hasWorker && !_proxy.enabled) true];
    for (final viaWorker in passes) {
      for (final origin in viaWorker ? ordered.take(2) : ordered) {
        if (!viaWorker && _isCoolingDown(origin)) continue;
        try {
          final uri = kind == MirrorKind.piped
              ? _proxy.piped(origin, path, query, viaWorker)
              : _proxy.invidious(origin, path, query, viaWorker);
          final response = await _dio
              .getUri<dynamic>(uri)
              .timeout(timeout, onTimeout: () => throw DioException(
                    requestOptions: RequestOptions(path: uri.toString()),
                    type: DioExceptionType.connectionTimeout,
                  ));
          if (response.statusCode == 200 && response.data != null) {
            _sticky[kind] = origin;
            _failed.remove(origin);
            return response;
          }
          lastError = 'HTTP ${response.statusCode}';
        } catch (error) {
          lastError = error;
          if (!viaWorker) _failed[origin] = DateTime.now();
        }
      }
    }

    throw DioException(
      requestOptions: RequestOptions(path: path),
      message: 'Все зеркала ${kind.name} недоступны: $lastError',
    );
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
