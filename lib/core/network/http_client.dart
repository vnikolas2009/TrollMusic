import 'package:dio/dio.dart';

import '../config/app_config.dart';

Dio createDio() {
  return Dio(
    BaseOptions(
      connectTimeout: AppConfig.mirrorTimeout,
      receiveTimeout: AppConfig.requestTimeout,
      sendTimeout: AppConfig.requestTimeout,
      responseType: ResponseType.json,
      headers: {
        'user-agent': 'YSPlayer/1.0 (+https://github.com/vnikolas2009/YSPlayer)',
        'accept': 'application/json',
      },
      validateStatus: (code) => code != null && code < 500,
    ),
  );
}
