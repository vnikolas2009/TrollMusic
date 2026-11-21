import 'dart:io';

import '../storage/settings.dart';
import '../utils/proxy_address.dart';

/// Глобальная маршрутизация всех Dart-соединений (dio, кэширующий источник
/// аудио) через пользовательский HTTP-прокси — обход блокировок в сети.
class AppHttpOverrides extends HttpOverrides {
  AppHttpOverrides(this._settings);

  final Settings _settings;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    final proxy = normalizeProxyAddress(_settings.httpProxy);
    if (proxy.isNotEmpty) {
      client.findProxy = (uri) => 'PROXY $proxy; DIRECT';
      return client;
    }
    if (_settings.useSystemProxy) {
      try {
        client.findProxy = HttpClient.findProxyFromEnvironment;
        return client;
      } catch (_) {
        // Переменные окружения недоступны — работаем напрямую.
      }
    }
    client.findProxy = (uri) => 'DIRECT';
    return client;
  }
}
