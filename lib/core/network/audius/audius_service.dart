import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

/// Audius: открытый каталог независимых артистов с публичным API.
///
/// Каталог и аудиопоток доступны без авторизации, поэтому Audius — единственный
/// из новых источников, который играет напрямую «из коробки».
/// Документация: https://docs.audius.org/developers/api
class AudiusService {
  AudiusService({required Settings settings})
    : _dio = createDio(
        settings: settings,
        receiveTimeout: const Duration(seconds: 15),
      );

  static const _api = 'https://api.audius.co/v1';

  /// Имя приложения для статистики Audius (обязательный параметр API).
  static const appName = 'TrollMusic';

  /// Префикс идентификатора трека в приложении.
  static const idPrefix = 'au:';

  final Dio _dio;

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.parse('$_api/tracks/search').replace(
      queryParameters: {
        'query': trimmed,
        'limit': '${limit.clamp(1, 50)}',
        'app_name': appName,
      },
    );
    return _fetchTracks(uri, limit);
  }

  /// Тренды недели. [genre] — необязательный жанр Audius (например `Electronic`).
  Future<List<Track>> trending({int limit = 30, String? genre}) {
    final uri = Uri.parse('$_api/tracks/trending').replace(
      queryParameters: {
        'time': 'week',
        'limit': '${limit.clamp(1, 50)}',
        'app_name': appName,
        if (genre != null && genre.isNotEmpty) 'genre': genre,
      },
    );
    return _fetchTracks(uri, limit);
  }

  Future<List<Track>> _fetchTracks(Uri uri, int limit) async {
    try {
      final response = await _dio.getUri<String>(
        uri,
        options: Options(responseType: ResponseType.plain),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return const [];
      final body = response.data;
      if (body == null || body.isEmpty) return const [];
      return await parseJson(body, (raw) => parseAudiusTracks(raw, limit: limit));
    } catch (_) {
      return const [];
    }
  }

  /// Ссылка на поток трека.
  ///
  /// Эндпоинт `/stream` отвечает редиректом на узел с файлом; плееры (ExoPlayer,
  /// AVPlayer, `LockCachingAudioSource`) следуют редиректам сами, поэтому
  /// отдельный запрос за прямой ссылкой не нужен.
  Future<List<String>> audioUrls(String trackId) async {
    final id = audiusRawId(trackId);
    if (id.isEmpty) return const [];
    return [audiusStreamUrl(id)];
  }
}

/// Идентификатор Audius без префикса `au:`; пустая строка, если он некорректен.
String audiusRawId(String trackId) {
  final raw = trackId.startsWith(AudiusService.idPrefix)
      ? trackId.substring(AudiusService.idPrefix.length)
      : trackId;
  return RegExp(r'^[A-Za-z0-9]+$').hasMatch(raw) ? raw : '';
}

String audiusStreamUrl(String rawId) =>
    'https://api.audius.co/v1/tracks/$rawId/stream'
    '?app_name=${AudiusService.appName}';

/// Разбор ответа Audius (`{"data": [...]}`) в треки.
List<Track> parseAudiusTracks(String body, {int limit = 30}) {
  final json = jsonDecode(body);
  final data = json is Map ? json['data'] : null;
  if (data is! List) return const [];

  final out = <Track>[];
  final seen = <String>{};

  for (final item in data.whereType<Map>()) {
    if (out.length >= limit) break;

    final id = item['id'];
    if (id is! String || id.isEmpty || !seen.add(id)) continue;
    if (item['is_streamable'] == false || item['is_delete'] == true) continue;

    final user = item['user'];
    final artist = user is Map ? _str(user['name']) ?? _str(user['handle']) : null;

    out.add(
      Track(
        id: '${AudiusService.idPrefix}$id',
        title: _str(item['title']) ?? 'Без названия',
        artist: artist ?? 'Audius',
        album: _str(item['genre']) ?? '',
        duration: Duration(seconds: _int(item['duration'])),
        thumbnailUrl: _artwork(item['artwork']) ??
            (user is Map ? _artwork(user['profile_picture']) : null),
        source: TrackSource.audius,
      ),
    );
  }
  return out;
}

String? _artwork(Object? art) {
  if (art is! Map) return null;
  return _str(art['480x480']) ?? _str(art['1000x1000']) ?? _str(art['150x150']);
}

String? _str(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value) => value is num ? value.toInt() : 0;
