import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../config/app_config.dart';
import '../storage/settings.dart';
import 'doh_resolver.dart';
import 'split_proxy.dart';

/// Создаёт Dio с DNS-over-HTTPS и опциональным HTTP-прокси.
Dio createDio({
  Settings? settings,
  Map<String, String>? headers,
  Duration? connectTimeout,
  Duration? receiveTimeout,
  DohResolver? resolver,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout ?? AppConfig.connectTimeout,
      receiveTimeout: receiveTimeout ?? AppConfig.requestTimeout,
      sendTimeout: receiveTimeout ?? AppConfig.requestTimeout,
      responseType: ResponseType.json,
      headers: {
        ...AppConfig.defaultHeaders,
        ...?headers,
        ...?settings?.requestHeaders,
      },
      validateStatus: (code) => code != null && code < 500,
    ),
  );
  dio.httpClientAdapter = buildHttpClientAdapter(
    settings,
    resolver ?? DohResolver.shared,
  );
  return dio;
}

HttpClientAdapter buildHttpClientAdapter(
  Settings? settings,
  DohResolver resolver,
) {
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient()
        ..connectionTimeout = AppConfig.connectTimeout
        ..idleTimeout = const Duration(seconds: 15);
      configureProxy(client, settings);
      client.connectionFactory = resolver.connect;
      return client;
    },
  );
}

/// Приоритет: ручной HTTP-прокси → системный прокси → прямое соединение.
void configureProxy(HttpClient client, Settings? settings) {
  final raw = settings?.httpProxy.trim() ?? '';
  if (raw.isNotEmpty && _applyManualProxy(client, raw)) return;
  if (settings?.bypassDpi ?? false) {
    // Локальный прокси режет TLS ClientHello, чтобы фильтр по SNI не сработал.
    client.findProxy = (uri) => uri.scheme == 'https' && SplitProxy.shared.running
        ? 'PROXY 127.0.0.1:${SplitProxy.shared.port}'
        : 'DIRECT';
    return;
  }
  if (settings?.useSystemProxy ?? true) {
    try {
      client.findProxy = HttpClient.findProxyFromEnvironment;
    } catch (_) {
      // Переменные окружения недоступны — работаем напрямую.
    }
  }
}

bool _applyManualProxy(HttpClient client, String raw) {
  final normalized = raw.contains('://') ? raw : 'http://$raw';
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.isEmpty) return false;

  final port = uri.hasPort ? uri.port : 8080;
  final info = uri.userInfo;
  final user = info.isEmpty
      ? null
      : Uri.decodeComponent(info.contains(':') ? info.split(':').first : info);
  final pass = info.contains(':')
      ? Uri.decodeComponent(info.split(':').skip(1).join(':'))
      : null;

  try {
    if (user != null && user.isNotEmpty) {
      client.addProxyCredentials(
        uri.host,
        port,
        'Basic',
        HttpClientBasicCredentials(user, pass ?? ''),
      );
    }
    client.findProxy = (_) => 'PROXY ${uri.host}:$port';
    return true;
  } catch (_) {
    return false;
  }
}
