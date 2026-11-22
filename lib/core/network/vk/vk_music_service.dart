import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

/// VK Музыка через метод `audio.*` VK API.
///
/// Важное ограничение: VK закрыл `audio.*` для обычных приложений, поэтому
/// сервис работает только с личным токеном пользователя (Настройки → VK
/// Музыка) и только пока VK разрешает такому токену эти методы. В приложение
/// не вшито ни токенов, ни ключей чужих клиентов; без токена сервис ничего не
/// запрашивает и возвращает пустой список.
///
/// Токен отправляется в теле POST-запроса, а не в URL, чтобы он не попадал
/// в логи и историю.
class VkMusicService {
  VkMusicService({required Settings settings})
    : _settings = settings,
      _dio = createDio(
        settings: settings,
        receiveTimeout: const Duration(seconds: 15),
      );

  static const _api = 'https://api.vk.com/method';
  static const _version = '5.131';

  /// Префикс идентификатора трека в приложении.
  static const idPrefix = 'vk:';

  final Settings _settings;
  final Dio _dio;

  bool get hasToken => _settings.vkToken.isNotEmpty;

  Future<List<Track>> search(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !hasToken) return const [];

    final body = await _call('audio.search', {
      'q': trimmed,
      'count': '${limit.clamp(1, 100)}',
      'auto_complete': '1',
    });
    if (body == null) return const [];
    return parseJson(body, (raw) => parseVkAudio(raw, limit: limit));
  }

  /// Ссылка на поток. VK отдаёт её только владельцу токена и ненадолго,
  /// поэтому ссылка запрашивается в момент воспроизведения, а не хранится.
  Future<List<String>> audioUrls(String trackId) async {
    if (!hasToken) return const [];
    final id = vkRawId(trackId);
    if (id.isEmpty) return const [];

    final body = await _call('audio.getById', {'audios': id});
    if (body == null) return const [];

    final url = vkStreamUrl(body);
    return url == null ? const [] : [url];
  }

  Future<String?> _call(String method, Map<String, String> params) async {
    try {
      final response = await _dio.postUri<String>(
        Uri.parse('$_api/$method'),
        data: {...params, 'access_token': _settings.vkToken, 'v': _version},
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) return null;
      final body = response.data;
      return (body == null || body.isEmpty) ? null : body;
    } catch (_) {
      return null;
    }
  }
}

/// Идентификатор `ownerId_audioId` без префикса `vk:`; пустая строка,
/// если он некорректен. `ownerId` может быть отрицательным (сообщества).
String vkRawId(String trackId) {
  final raw = trackId.startsWith(VkMusicService.idPrefix)
      ? trackId.substring(VkMusicService.idPrefix.length)
      : trackId;
  return RegExp(r'^-?\d+_\d+$').hasMatch(raw) ? raw : '';
}

/// Ответ VK с ошибкой (`{"error": {...}}`), в том числе «метод закрыт».
bool isVkError(String body) {
  try {
    final json = jsonDecode(body);
    return json is Map && json['error'] != null;
  } catch (_) {
    return false;
  }
}

/// Разбор `audio.search` в треки. Ссылки (`url`) намеренно не сохраняются.
List<Track> parseVkAudio(String body, {int limit = 30}) {
  final json = jsonDecode(body);
  if (json is! Map || json['error'] != null) return const [];

  final response = json['response'];
  final items = response is Map ? response['items'] : response;
  if (items is! List) return const [];

  final out = <Track>[];
  final seen = <String>{};

  for (final item in items.whereType<Map>()) {
    if (out.length >= limit) break;

    final owner = item['owner_id'];
    final audio = item['id'];
    if (owner is! num || audio is! num) continue;

    final id = '${owner.toInt()}_${audio.toInt()}';
    if (!seen.add(id)) continue;

    final album = item['album'];
    final thumb = album is Map ? album['thumb'] : null;

    out.add(
      Track(
        id: '${VkMusicService.idPrefix}$id',
        title: _str(item['title']) ?? 'Без названия',
        artist: _str(item['artist']) ?? 'VK Музыка',
        album: album is Map ? _str(album['title']) ?? '' : '',
        duration: Duration(seconds: _int(item['duration'])),
        thumbnailUrl: thumb is Map
            ? _str(thumb['photo_300']) ??
                  _str(thumb['photo_270']) ??
                  _str(thumb['photo_600'])
            : null,
        explicit: item['is_explicit'] == true,
        source: TrackSource.vk,
      ),
    );
  }
  return out;
}

/// Достаёт https-ссылку на поток из ответа `audio.getById`.
String? vkStreamUrl(String body) {
  final json = jsonDecode(body);
  if (json is! Map || json['error'] != null) return null;

  final response = json['response'];
  final first = response is List && response.isNotEmpty ? response.first : null;
  final url = first is Map ? _str(first['url']) : null;
  if (url == null) return null;

  final uri = Uri.tryParse(url);
  return (uri != null && uri.scheme == 'https') ? url : null;
}

String? _str(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value) => value is num ? value.toInt() : 0;
