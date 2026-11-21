import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:socks5_proxy/socks_client.dart';

import '../config/app_config.dart';
import '../storage/settings.dart';

/// Создаёт Dio с поддержкой системного и ручного прокси (HTTP/HTTPS/SOCKS5).
Dio createDio({
  Settings? settings,
  Map<String, String>? headers,
  Duration? connectTimeout,
  Duration? receiveTimeout,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout ?? AppConfig.mirrorTimeout,
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
  dio.httpClientAdapter = buildHttpClientAdapter(settings);
  return dio;
}

HttpClientAdapter buildHttpClientAdapter(Settings? settings) {
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..idleTimeout = const Duration(seconds: 15);
      configureProxy(client, settings);
      return client;
    },
  );
}

/// Настраивает прокси у [HttpClient].
///
/// Приоритет: ручной прокси из настроек → системный прокси → прямое соединение.
void configureProxy(HttpClient client, Settings? settings) {
  final raw = settings?.httpProxy.trim() ?? '';
  if (raw.isNotEmpty && _applyManualProxy(client, raw)) return;
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

  final scheme = uri.scheme.toLowerCase();
  final isSocks = scheme == 'socks' || scheme == 'socks5';
  final port = uri.hasPort ? uri.port : (isSocks ? 1080 : 8080);
  final user = uri.userInfo.contains(':')
      ? Uri.decodeComponent(uri.userInfo.split(':').first)
      : (uri.userInfo.isEmpty ? null : Uri.decodeComponent(uri.userInfo));
  final pass = uri.userInfo.contains(':')
      ? Uri.decodeComponent(uri.userInfo.split(':').skip(1).join(':'))
      : null;

  try {
    if (isSocks) {
      final address = InternetAddress.tryParse(uri.host);
      if (address == null) return false;
      SocksTCPClient.assignToHttpClient(client, [
        ProxySettings(
          address,
          port,
          username: user,
          password: pass,
        ),
      ]);
      return true;
    }

    if (user != null && user.isNotEmpty) {
      // С Dart 3.9 (Flutter 3.47+) addProxyCredentials принимает объект
      // HttpClientCredentials, а не готовую строку заголовка.
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
