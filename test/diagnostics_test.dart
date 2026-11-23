import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trollmusic/core/network/diagnostics.dart';

void main() {
  test('отчёт перечисляет доступные и недоступные серверы', () {
    const a = DiagTarget('SoundCloud', 'https://a', '');
    const b = DiagTarget('YouTube', 'https://b', '');
    final text = formatReport([
      const DiagResult(
        target: a,
        reachable: true,
        elapsed: Duration(milliseconds: 120),
        status: 404,
      ),
      const DiagResult(
        target: b,
        reachable: false,
        elapsed: Duration(seconds: 8),
        error: 'таймаут',
      ),
    ]);
    expect(text, contains('OK  SoundCloud: HTTP 404, 120 мс'));
    expect(text, contains('НЕТ YouTube: таймаут'));
  });

  test('цели диагностики включают бэкенд из настроек', () {
    final targets = diagnosticTargets('https://example.test');
    expect(targets.any((t) => t.url == 'https://example.test'), isTrue);
    expect(targets.map((t) => t.name), contains('SoundCloud'));
  });

  test('ошибка Dio описывается по-русски', () {
    final text = describeNetworkError(DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionTimeout,
    ));
    expect(text, contains('соединение'));
  });
}
