import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/network/http_client.dart';
import '../../core/utils/web_audio.dart';

/// Скачивает аудиофайл по прямой ссылке, найденной во встроенном браузере.
class WebDownloadService {
  WebDownloadService({Dio? dio}) : _dio = dio ?? createDio(receiveTimeout: const Duration(minutes: 10));

  final Dio _dio;

  /// Сохраняет файл во временную папку и возвращает его. [referer] нужен
  /// некоторым сайтам, чтобы отдать файл. Бросает [Exception] с понятным
  /// текстом, если ответ — не аудио.
  Future<File> download(
    Uri url, {
    String? referer,
    String? pageTitle,
    void Function(double? progress)? onProgress,
    CancelToken? cancel,
  }) async {
    final dir = await getTemporaryDirectory();
    final folder = await Directory(p.join(dir.path, 'web_downloads')).create(recursive: true);
    final tmp = File(p.join(folder.path, 'dl_${DateTime.now().microsecondsSinceEpoch}.part'));

    try {
      final response = await _dio.download(
        url.toString(),
        tmp.path,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {if (referer != null) 'referer': referer, 'accept': 'audio/*,*/*;q=0.8'},
        ),
        onReceiveProgress: (received, total) =>
            onProgress?.call(total > 0 ? received / total : null),
      );

      final code = response.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        throw Exception('Сервер ответил кодом $code');
      }

      final type = response.headers.value('content-type');
      final byUrl = looksLikeAudioUrl(url);
      if (!isDownloadableAudio(type) && !byUrl) {
        throw Exception('По ссылке не аудиофайл');
      }
      if (await tmp.length() < 1024) {
        throw Exception('Файл пустой или слишком маленький');
      }

      final name = downloadFileName(
        url: url,
        contentDisposition: response.headers.value('content-disposition'),
        contentType: type,
        pageTitle: pageTitle,
      );
      final target = File(p.join(folder.path, name));
      if (await target.exists()) await target.delete();
      return await tmp.rename(target.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }
}
