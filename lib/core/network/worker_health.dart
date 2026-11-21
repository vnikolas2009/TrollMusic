import 'package:dio/dio.dart';

import '../storage/settings.dart';
import 'http_client.dart';
import 'proxy.dart';

/// Состояние Cloudflare Worker'а, доступного из настроек приложения.
class WorkerStatus {
  const WorkerStatus({
    required this.configured,
    required this.ok,
    this.latencyMs,
    this.detail,
    this.checkedAt,
  });

  /// Worker вообще указан в настройках.
  final bool configured;

  /// Проверка `/health` прошла (и, для deep-режима, живо хотя бы одно зеркало).
  final bool ok;
  final int? latencyMs;
  final String? detail;
  final DateTime? checkedAt;

  static const unknown = WorkerStatus(configured: false, ok: false);

  String get label {
    if (!configured) return 'Worker не указан';
    if (ok) {
      final ms = latencyMs == null ? '' : ' · $latencyMs мс';
      return 'Worker доступен$ms';
    }
    return 'Worker недоступен${detail == null ? '' : ' · $detail'}';
  }
}

/// Проверка Worker'а и простой circuit breaker.
///
/// Если Worker не ответил несколько раз подряд, аудио-кандидаты, идущие через
/// него, временно не предлагаются — чтобы плеер не терял секунды на каждом
/// треке. Через [_suspendFor] состояние сбрасывается.
class WorkerHealth {
  WorkerHealth({
    required Settings settings,
    required ProxyConfig proxy,
    Dio? dio,
  })  : _proxy = proxy,
        _dio = dio ??
            createDio(
              settings: settings,
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
            );

  final ProxyConfig _proxy;
  final Dio _dio;

  static const _cacheFor = Duration(seconds: 60);
  static const _suspendFor = Duration(minutes: 5);
  static const _maxFailures = 2;

  WorkerStatus _status = WorkerStatus.unknown;
  DateTime? _checkedAt;
  Future<WorkerStatus>? _inFlight;
  int _failures = 0;
  DateTime? _suspendedUntil;

  WorkerStatus get status => _status;

  /// Стоит ли сейчас вообще предлагать Worker как канал для аудио.
  bool get usable => _proxy.hasWorker && !isSuspended;

  /// [url] ведёт на этот Worker (аудиопоток или пасsthrough-запрос).
  bool owns(String url) => _proxy.hasWorker && url.startsWith(_proxy.workerUrl);

  /// Worker временно исключён после серии ошибок.
  bool get isSuspended {
    final until = _suspendedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _suspendedUntil = null;
    _failures = 0;
    return false;
  }

  /// Проверка доступности. Результат кэшируется на минуту.
  Future<WorkerStatus> check({bool force = false, bool deep = false}) {
    if (!_proxy.hasWorker) {
      _status = const WorkerStatus(configured: false, ok: false);
      _checkedAt = DateTime.now();
      return Future.value(_status);
    }
    final checkedAt = _checkedAt;
    if (!force &&
        !deep &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheFor) {
      return Future.value(_status);
    }
    final running = _inFlight;
    if (running != null && !force) return running;

    final future = _run(deep: deep);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<WorkerStatus> _run({required bool deep}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('${_proxy.workerUrl}/health')
          .replace(queryParameters: deep ? {'deep': '1'} : null);
      final response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          responseType: ResponseType.json,
          // /health публичный, поэтому достаточно минимального Accept.
          headers: const {'accept': 'application/json'},
        ),
      );
      stopwatch.stop();
      final data = response.data;
      final ok = response.statusCode == 200 &&
          data is Map &&
          data['ok'] == true;
      _record(ok, stopwatch.elapsedMilliseconds,
          detail: ok ? null : 'HTTP ${response.statusCode}');
      return _status;
    } catch (error) {
      stopwatch.stop();
      _record(false, stopwatch.elapsedMilliseconds,
          detail: _describe(error));
      return _status;
    }
  }

  /// Вызывается плеером, когда аудиопоток через Worker не открылся.
  void reportFailure([String? detail]) {
    _record(false, null, detail: detail ?? 'stream failed');
  }

  /// Вызывается после успешного воспроизведения через Worker.
  void reportSuccess() {
    _failures = 0;
    _suspendedUntil = null;
    _status = WorkerStatus(
      configured: _proxy.hasWorker,
      ok: true,
      latencyMs: _status.latencyMs,
      checkedAt: DateTime.now(),
    );
  }

  void reset() {
    _status = WorkerStatus.unknown;
    _checkedAt = null;
    _failures = 0;
    _suspendedUntil = null;
    _inFlight = null;
  }

  void _record(bool ok, int? latencyMs, {String? detail}) {
    _checkedAt = DateTime.now();
    _status = WorkerStatus(
      configured: _proxy.hasWorker,
      ok: ok,
      latencyMs: latencyMs,
      detail: detail,
      checkedAt: _checkedAt,
    );
    if (ok) {
      _failures = 0;
      _suspendedUntil = null;
      return;
    }
    _failures++;
    if (_failures >= _maxFailures) {
      _suspendedUntil = DateTime.now().add(_suspendFor);
    }
  }

  String _describe(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout => 'таймаут подключения',
        DioExceptionType.receiveTimeout => 'таймаут ответа',
        DioExceptionType.connectionError => 'нет соединения',
        _ => error.message ?? error.type.name,
      };
    }
    return error.toString();
  }
}
