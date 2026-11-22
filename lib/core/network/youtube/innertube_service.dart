import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../../utils/json_isolate.dart';
import '../http_client.dart';

/// Фоллбэк на публичный InnerTube YouTube без ключей и OAuth.
///
/// Для получения аудио используются клиенты `ANDROID_VR` и `IOS`: они отдают
/// прямые ссылки googlevideo.com без подписи плеера и PO-токена.
class InnerTubeService {
  InnerTubeService({required Settings settings})
      : _settings = settings,
        _dio = createDio(
          settings: settings,
          receiveTimeout: const Duration(seconds: 15),
        );

  final Settings _settings;
  final Dio _dio;

  static const _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _base = 'https://www.youtube.com/youtubei/v1';

  static const androidVr = InnerTubeClientProfile(
    name: 'ANDROID_VR',
    version: '1.60.19',
    clientId: 28,
    userAgent: 'com.google.android.apps.youtube.vr.oculus/1.60.19 '
        '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    extra: {
      'deviceMake': 'Oculus',
      'deviceModel': 'Quest 3',
      'osName': 'Android',
      'osVersion': '12L',
      'androidSdkVersion': 32,
    },
  );

  static const ios = InnerTubeClientProfile(
    name: 'IOS',
    version: '19.45.4',
    clientId: 5,
    userAgent:
        'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)',
    extra: {
      'deviceMake': 'Apple',
      'deviceModel': 'iPhone16,2',
      'osName': 'iPhone',
      'osVersion': '18.1.0.22B83',
    },
  );

  static const web = InnerTubeClientProfile(
    name: 'WEB',
    version: '2.20241126.01.00',
    clientId: 1,
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  );

  static const _playerClients = [androidVr, ios];

  /// Заголовки, с которыми нужно скачивать потоки конкретного клиента.
  static const Map<String, String> androidVrStreamHeaders = {
    'User-Agent': 'com.google.android.apps.youtube.vr.oculus/1.60.19 '
        '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    'Accept': '*/*',
  };

  Future<List<Track>> search(String query, {int limit = 30}) async {
    for (final client in const [web, androidVr]) {
      try {
        final body = await _post('search', {
          'query': query,
          'params': 'EgIQAQ%3D%3D',
          'context': contextFor(client),
        }, client);
        final tracks = await parseJson(
          body,
          (raw) => parseSearchBody(raw, limit: limit),
        );
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        // Следующий клиент.
      }
    }
    return const [];
  }

  /// Ссылки на аудио: сначала прямые форматы, затем HLS-манифест.
  Future<List<String>> audioUrls(String videoId) async {
    final target = _settings.bitrate;
    final preferOpus = _settings.preferOpus;
    for (final client in _playerClients) {
      try {
        final body = await _post('player', {
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
          'context': contextFor(client),
        }, client);
        final urls = await parseJson(
          body,
          (raw) => parseAudioBody(raw, target: target, preferOpus: preferOpus),
        );
        if (urls.isNotEmpty) return urls;
      } catch (_) {
        // Следующий клиент.
      }
    }
    return const [];
  }

  Future<String> _post(
    String endpoint,
    Map<String, dynamic> body,
    InnerTubeClientProfile client,
  ) async {
    final response = await _dio.postUri<String>(
      Uri.parse('$_base/$endpoint?key=$_apiKey&prettyPrint=false'),
      data: jsonEncode(body),
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.jsonContentType,
        headers: {
          'user-agent': client.userAgent,
          'x-youtube-client-name': '${client.clientId}',
          'x-youtube-client-version': client.version,
          'origin': 'https://www.youtube.com',
          'referer': 'https://www.youtube.com/',
        },
      ),
    );
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status >= 400 || data == null || data.isEmpty) {
      throw StateError('InnerTube $endpoint: HTTP $status');
    }
    return data;
  }

  static Map<String, dynamic> contextFor(InnerTubeClientProfile client) => {
        'client': {
          'clientName': client.name,
          'clientVersion': client.version,
          'hl': 'ru',
          'gl': 'RU',
          ...client.extra,
        },
      };
}

class InnerTubeClientProfile {
  const InnerTubeClientProfile({
    required this.name,
    required this.version,
    required this.clientId,
    required this.userAgent,
    this.extra = const {},
  });

  final String name;
  final String version;
  final int clientId;
  final String userAgent;
  final Map<String, dynamic> extra;
}

/// Разбор ответа `search`. Top-level: выполняется в изоляте.
List<Track> parseSearchBody(String body, {int limit = 30}) {
  final data = jsonDecode(body);
  final tracks = <Track>[];
  final seen = <String>{};

  void walk(dynamic node) {
    if (tracks.length >= limit) return;
    if (node is Map) {
      final renderer = node['videoRenderer'];
      if (renderer is Map) {
        final track = _videoToTrack(renderer);
        if (track != null && seen.add(track.id)) tracks.add(track);
      }
      for (final value in node.values) {
        walk(value);
      }
    } else if (node is List) {
      for (final value in node) {
        walk(value);
      }
    }
  }

  walk(data);
  return tracks;
}

/// Разбор ответа `player`. Top-level: выполняется в изоляте.
List<String> parseAudioBody(
  String body, {
  required int target,
  required bool preferOpus,
}) {
  final data = jsonDecode(body);
  if (data is! Map) return const [];
  final streaming = data['streamingData'];
  if (streaming is! Map) return const [];

  final formats = (streaming['adaptiveFormats'] as List?) ?? const [];
  final scored = <({int score, String url})>[];
  for (final raw in formats) {
    if (raw is! Map) continue;
    final mime = '${raw['mimeType'] ?? ''}'.toLowerCase();
    if (!mime.startsWith('audio/')) continue;
    final url = raw['url'];
    if (url is! String || url.isEmpty) continue;
    final bitrate = (raw['bitrate'] as num?)?.toInt() ?? 128000;
    final kbps = bitrate > 10000 ? bitrate ~/ 1000 : bitrate;
    final isOpus = mime.contains('opus') || mime.contains('webm');
    var score = kbps - (kbps - target).abs() ~/ 2;
    if (isOpus) score += preferOpus ? 60 : -40;
    scored.add((score: score, url: url));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));

  final out = <String>[];
  for (final item in scored) {
    if (!out.contains(item.url)) out.add(item.url);
    if (out.length >= 3) break;
  }
  final hls = streaming['hlsManifestUrl'];
  if (hls is String && hls.isNotEmpty) out.add(hls);
  return out;
}

Track? _videoToTrack(Map json) {
  final id = json['videoId'];
  if (id is! String || id.isEmpty) return null;
  final title = _runsText(json['title']) ?? 'Без названия';
  final artist = _runsText(json['ownerText']) ??
      _runsText(json['longBylineText']) ??
      _runsText(json['shortBylineText']) ??
      'YouTube';
  final duration = _parseDuration(_runsText(json['lengthText']));
  final thumbs = json['thumbnail'] is Map ? json['thumbnail']['thumbnails'] : null;
  String? thumb;
  if (thumbs is List && thumbs.isNotEmpty) {
    final last = thumbs.last;
    if (last is Map && last['url'] is String) thumb = last['url'] as String;
  }
  return Track(
    id: id,
    title: title,
    artist: artist,
    duration: duration,
    thumbnailUrl: thumb,
    source: TrackSource.youtube,
  );
}

String? _runsText(dynamic node) {
  if (node is Map) {
    final runs = node['runs'];
    if (runs is List && runs.isNotEmpty) {
      return runs.whereType<Map>().map((r) => '${r['text'] ?? ''}').join().trim();
    }
    final simple = node['simpleText'];
    if (simple is String) return simple;
  }
  if (node is String) return node;
  return null;
}

Duration _parseDuration(String? raw) {
  if (raw == null || raw.isEmpty) return Duration.zero;
  var seconds = 0;
  for (final part in raw.split(':')) {
    seconds = seconds * 60 + (int.tryParse(part.trim()) ?? 0);
  }
  return Duration(seconds: seconds);
}
