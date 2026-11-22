import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

/// Яндекс Музыка (неофициальный клиентский API `api.music.yandex.net`).
///
/// * Поиск и чарт работают без авторизации — это только метаданные.
/// * Прямая ссылка на аудио строится только с личным OAuth-токеном
///   пользователя (Настройки → Яндекс Музыка) и только в рамках его подписки.
///   Без токена воспроизведение подбирается на других источниках
///   (`AudioResolverService`), как и для Spotify.
///
/// Токен отправляется исключительно на `api.music.yandex.net`; на хранилище
/// файлов (`storage.mds.yandex.net`) он не уходит.
class YandexMusicService {
  YandexMusicService({required Settings settings})
    : _settings = settings,
      _dio = createDio(
        settings: settings,
        receiveTimeout: const Duration(seconds: 15),
        headers: const {
          'x-yandex-music-client': 'YandexMusicAndroid/24023231',
          'user-agent': 'Yandex-Music-API',
        },
      );

  static const _api = 'https://api.music.yandex.net';

  /// Префикс идентификатора трека в приложении.
  static const idPrefix = 'ym:';

  final Settings _settings;
  final Dio _dio;

  bool get hasToken => _settings.yandexToken.isNotEmpty;

  Options _apiOptions() {
    final token = _settings.yandexToken;
    return Options(
      responseType: ResponseType.plain,
      headers: {if (token.isNotEmpty) 'authorization': 'OAuth $token'},
    );
  }

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final uri = Uri.parse('$_api/search').replace(
      queryParameters: {
        'text': trimmed,
        'type': 'track',
        'page': '0',
        'nocorrect': 'false',
      },
    );
    final body = await _get(uri);
    if (body == null) return const [];
    return parseJson(body, (raw) => parseYandexSearch(raw, limit: limit));
  }

  /// Чарт Яндекс Музыки; при ошибке или пустом ответе — пустой список.
  Future<List<Track>> chart({int limit = 30}) async {
    final body = await _get(Uri.parse('$_api/landing3/chart'));
    if (body == null) return const [];
    return parseJson(body, (raw) => parseYandexChart(raw, limit: limit));
  }

  /// Прямая ссылка на mp3. Требует токен; без него возвращает пустой список.
  Future<List<String>> audioUrls(String trackId) async {
    if (!hasToken) return const [];
    final id = yandexRawId(trackId);
    if (id.isEmpty) return const [];

    try {
      final info = await _get(Uri.parse('$_api/tracks/$id/download-info'));
      if (info == null) return const [];

      final variant = pickYandexVariant(
        parseYandexDownloadInfo(info),
        targetBitrate: _settings.bitrate,
      );
      if (variant == null) return const [];

      final infoUri = Uri.tryParse(yandexJsonInfoUrl(variant.url));
      if (infoUri == null || infoUri.scheme != 'https') return const [];

      // Хранилище файлов — другой хост: токен ему не передаём.
      final response = await _dio.getUri<String>(
        infoUri,
        options: Options(responseType: ResponseType.plain),
      );
      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status < 200 || status >= 300 || body == null) return const [];

      final link = yandexDirectLink(body);
      return link == null ? const [] : [link];
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _get(Uri uri) async {
    try {
      final response = await _dio.getUri<String>(uri, options: _apiOptions());
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final body = response.data;
      return (body == null || body.isEmpty) ? null : body;
    } catch (_) {
      return null;
    }
  }
}

/// Соль подписи прямых ссылок. Она публично описана в открытых клиентах
/// Яндекс Музыки и не является секретом пользователя.
const _signSalt = 'XGRlBW9FXlekgbPrRHuSiA';

/// Идентификатор без префикса `ym:`; пустая строка, если он некорректен.
/// Допустимы `123` и `123:456` (трек:альбом).
String yandexRawId(String trackId) {
  final raw = trackId.startsWith(YandexMusicService.idPrefix)
      ? trackId.substring(YandexMusicService.idPrefix.length)
      : trackId;
  return RegExp(r'^\d+(:\d+)?$').hasMatch(raw) ? raw : '';
}

/// Вариант файла из `download-info`.
typedef YandexVariant = ({int bitrate, String url});

/// Разбор `download-info`: только mp3 со ссылкой на информацию о файле.
List<YandexVariant> parseYandexDownloadInfo(String body) {
  final json = jsonDecode(body);
  final result = json is Map ? json['result'] : null;
  if (result is! List) return const [];

  final out = <YandexVariant>[];
  for (final item in result.whereType<Map>()) {
    if (item['codec'] != 'mp3') continue;
    final url = item['downloadInfoUrl'];
    if (url is! String || url.isEmpty) continue;
    out.add((bitrate: _int(item['bitrateInKbps']), url: url));
  }
  return out;
}

/// Выбирает самый высокий битрейт, не превышающий [targetBitrate];
/// если все выше цели — самый низкий.
YandexVariant? pickYandexVariant(
  List<YandexVariant> variants, {
  required int targetBitrate,
}) {
  if (variants.isEmpty) return null;
  final sorted = [...variants]..sort((a, b) => a.bitrate.compareTo(b.bitrate));
  YandexVariant? best;
  for (final variant in sorted) {
    if (variant.bitrate <= targetBitrate) best = variant;
  }
  return best ?? sorted.first;
}

/// Добавляет `format=json` к ссылке `downloadInfoUrl`.
String yandexJsonInfoUrl(String url) {
  if (url.contains('format=json')) return url;
  return '$url${url.contains('?') ? '&' : '?'}format=json';
}

/// Собирает прямую ссылку из ответа `downloadInfoUrl?format=json`:
/// `https://{host}/get-mp3/{md5(salt + path без '/' + s)}/{ts}{path}`.
String? yandexDirectLink(String body) {
  final json = jsonDecode(body);
  if (json is! Map) return null;

  final host = json['host'];
  final path = json['path'];
  final ts = json['ts']?.toString();
  final s = json['s']?.toString();

  if (host is! String || !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) {
    return null;
  }
  if (path is! String || !path.startsWith('/')) return null;
  if (ts == null || ts.isEmpty || s == null || s.isEmpty) return null;

  final sign = md5.convert(utf8.encode('$_signSalt${path.substring(1)}$s'));
  return 'https://$host/get-mp3/$sign/$ts$path';
}

/// Обложка Яндекса: `avatars.yandex.net/.../%%` → `https://.../400x400`.
String? yandexCoverUrl(String? uri, {int size = 400}) {
  if (uri == null || uri.trim().isEmpty) return null;
  final sized = uri.trim().replaceAll('%%', '${size}x$size');
  return sized.startsWith('http') ? sized : 'https://$sized';
}

/// Разбор `/search?type=track`.
List<Track> parseYandexSearch(String body, {int limit = 30}) {
  final json = jsonDecode(body);
  final result = json is Map ? json['result'] : null;
  final tracks = result is Map ? result['tracks'] : null;
  final results = tracks is Map ? tracks['results'] : null;
  if (results is! List) return const [];
  return _tracksFrom(results, limit);
}

/// Разбор `/landing3/chart`: элементы — `{track: {...}}` или сами треки.
List<Track> parseYandexChart(String body, {int limit = 30}) {
  final json = jsonDecode(body);
  final result = json is Map ? json['result'] : null;
  final chart = result is Map ? result['chart'] : null;
  final items = chart is Map ? chart['tracks'] : null;
  if (items is! List) return const [];

  final unwrapped = [
    for (final item in items.whereType<Map>())
      item['track'] is Map ? item['track'] : item,
  ];
  return _tracksFrom(unwrapped, limit);
}

List<Track> _tracksFrom(List<Object?> items, int limit) {
  final out = <Track>[];
  final seen = <String>{};

  for (final raw in items.whereType<Map>()) {
    if (out.length >= limit) break;

    final rawId = raw['id'];
    final id = rawId is String
        ? rawId.trim()
        : (rawId is num ? '${rawId.toInt()}' : '');
    if (id.isEmpty || !seen.add(id)) continue;
    if (raw['available'] == false) continue;

    final version = _str(raw['version']);
    final title = _str(raw['title']) ?? 'Без названия';

    final artists = raw['artists'];
    final artistNames = artists is List
        ? [
            for (final artist in artists.whereType<Map>())
              if (_str(artist['name']) != null) _str(artist['name'])!,
          ]
        : const <String>[];

    final albums = raw['albums'];
    final album = albums is List && albums.isNotEmpty && albums.first is Map
        ? albums.first as Map
        : null;
    final albumId = album?['id'];

    out.add(
      Track(
        id: '${YandexMusicService.idPrefix}$id',
        title: version == null ? title : '$title ($version)',
        artist: artistNames.isEmpty ? 'Яндекс Музыка' : artistNames.join(', '),
        album: _str(album?['title']) ?? '',
        duration: Duration(milliseconds: _int(raw['durationMs'])),
        thumbnailUrl: yandexCoverUrl(
          _str(raw['coverUri']) ?? _str(album?['coverUri']),
        ),
        explicit: raw['contentWarning'] == 'explicit',
        source: TrackSource.yandex,
        albumId: albumId == null ? null : '$albumId',
      ),
    );
  }
  return out;
}

String? _str(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value) => value is num ? value.toInt() : 0;
