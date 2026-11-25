import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Общий Dio для запросов к сервисам текстов песен.
Dio createDio({Duration? connectTimeout, Duration? receiveTimeout}) {
  return Dio(
    BaseOptions(
      connectTimeout: connectTimeout ?? AppConfig.connectTimeout,
      receiveTimeout: receiveTimeout ?? AppConfig.requestTimeout,
      sendTimeout: AppConfig.requestTimeout,
      responseType: ResponseType.json,
      headers: const {
        'user-agent': AppConfig.userAgent,
        'accept': 'application/json, text/plain, */*',
      },
      validateStatus: (code) => code != null && code < 500,
    ),
  );
}
