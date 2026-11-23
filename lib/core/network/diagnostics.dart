import 'package:dio/dio.dart';

/// Одна проверка доступности сервера.
class DiagTarget {
  const DiagTarget(this.name, this.url, this.purpose);

  final String name;
  final String url;

  /// Для чего приложению этот сервер (показывается в отчёте).
  final String purpose;
}

class DiagResult {
  const DiagResult({
    required this.target,
    required this.reachable,
    required this.elapsed,
    this.status,
    this.error,
  });

  final DiagTarget target;

  /// Сервер ответил (любой код ниже 500, в том числе 404 на корень API).
  final bool reachable;
  final Duration elapsed;
  final int? status;
  final String? error;
}

List<DiagTarget> diagnosticTargets(String apiBase) => [
      const DiagTarget(
        'SoundCloud',
        'https://api-v2.soundcloud.com/',
        'поиск и потоки (основной источник без VPN)',
      ),
      const DiagTarget(
        'YouTube',
        'https://www.youtube.com/generate_204',
        'поиск YouTube Music',
      ),
      const DiagTarget(
        'YouTube (потоки)',
        'https://redirector.googlevideo.com/',
        'аудиопотоки YouTube',
      ),
      const DiagTarget('Audius', 'https://api.audius.co/', 'каталог Audius'),
      const DiagTarget(
        'Яндекс Музыка',
        'https://api.music.yandex.net/',
        'каталог Яндекс Музыки',
      ),
      const DiagTarget('LRCLIB', 'https://lrclib.net/', 'тексты песен'),
      const DiagTarget(
        'DNS 8.8.8.8',
        'https://8.8.8.8/resolve?name=example.com&type=A',
        'DNS-over-HTTPS по IP',
      ),
      const DiagTarget(
        'DNS dns.google',
        'https://dns.google/resolve?name=example.com&type=A',
        'DNS-over-HTTPS',
      ),
      const DiagTarget(
        'DNS Cloudflare',
        'https://cloudflare-dns.com/dns-query?name=example.com&type=A',
        'DNS-over-HTTPS',
      ),
      DiagTarget(
        'Бэкенд (Vercel)',
        apiBase,
        'только метаданные Spotify; плееру не нужен',
      ),
    ];

/// Короткое объяснение ошибки Dio для человека.
String describeNetworkError(Object error) {
  if (error is DioException) {
    final cause = error.error?.toString();
    final suffix = cause == null || cause.isEmpty ? '' : ' ($cause)';
    return switch (error.type) {
      DioExceptionType.connectionTimeout =>
        'не удалось установить соединение за отведённое время$suffix',
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'сервер не ответил вовремя',
      DioExceptionType.badCertificate => 'ошибка сертификата (возможна подмена)',
      DioExceptionType.connectionError => 'соединение сброшено или заблокировано$suffix',
      _ => 'ошибка запроса$suffix',
    };
  }
  return error.toString();
}

Future<DiagResult> probe(
  Dio dio,
  DiagTarget target, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final watch = Stopwatch()..start();
  try {
    final response = await dio.get<String>(
      target.url,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        headers: const {'accept': '*/*'},
      ),
    );
    final code = response.statusCode;
    return DiagResult(
      target: target,
      reachable: code != null && code < 500,
      elapsed: watch.elapsed,
      status: code,
    );
  } catch (error) {
    return DiagResult(
      target: target,
      reachable: false,
      elapsed: watch.elapsed,
      error: describeNetworkError(error),
    );
  }
}

/// Текстовый отчёт, который можно скопировать и прислать.
String formatReport(List<DiagResult> results) {
  final buffer = StringBuffer('TrollMusic: диагностика сети\n');
  for (final r in results) {
    final mark = r.reachable ? 'OK ' : 'НЕТ';
    final ms = r.elapsed.inMilliseconds;
    final detail = r.reachable ? 'HTTP ${r.status}, $ms мс' : (r.error ?? 'ошибка');
    buffer.writeln('$mark ${r.target.name}: $detail');
  }
  return buffer.toString().trimRight();
}
