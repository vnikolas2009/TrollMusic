import 'dart:io';

import '../storage/settings.dart';

/// Глобальная маршрутизация всех Dart-соединений (dio, кэширующий источник
/// аудио) через пользовательский HTTP-прокси — обход блокировок в сети.
class AppHttpOverrides extends HttpOverrides {
  AppHttpOverrides(this._settings);

  final Settings _settings;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final proxy = _settings.httpProxy;
      return proxy.isEmpty ? 'DIRECT' : 'PROXY $proxy; DIRECT';
    };
    return client;
  }
}
