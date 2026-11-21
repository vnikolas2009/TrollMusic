import 'package:dio/dio.dart';

import '../../../data/models/track.dart';
import '../../storage/settings.dart';
import '../http_client.dart';

/// Прямой клиент публичного InnerTube API YouTube.
///
/// Не требует ключей/OAuth, работает как последний фоллбэк, когда Piped и
/// Invidious недоступны. Возвращает прямые ссылки googlevideo.com.
class InnerTubeClient {
  InnerTubeClient({required Settings settings})
      : _settings = settings,
        _dio = createDio(
          settings: settings,
          receiveTimeout: const Duration(seconds: 15),
        );

  final Settings _settings;
  final Dio _dio;

  static const _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _base = 'https://www.youtube.com/youtubei/v1';

  static const _clients = <_ClientProfile>[
    _ClientProfile(
      name: 'ANDROID',
      version: '19.44.38',
      clientId: 3,
      userAgent: 'com.google.android.youtube/19.44.38 (Linux; U; Android 11) gzip',
      extra: {'androidSdkVersion': 30, 'osName': 'Android', 'osVersion': '11'},
    ),
    _ClientProfile(
      name: 'IOS',
      version: '19.45.4',
      clientId: 5,
      userAgent:
          'com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)',
      extra: {'deviceModel': 'iPhone16,2', 'osName': 'iPhone', 'osVersion': '18.1.0.22B83'},
    ),
    _ClientProfile(
      name: 'WEB',
      version: '2.20241126.01.00',
      clientId: 1,
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    ),
    _ClientProfile(
      name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      version: '2.0',
      clientId: 85,
      userAgent:
          'Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 '
              '(KHTML, like Gecko) Version/16.0 Safari/605.1.15',
    ),
  ];

  Future<List<Track>> search(String query, {int limit = 30}) async {
    for (final client in _clients) {
      try {
        final response = await _post(
          'search',
          {
            'query': query,
            'params': 'EgIQAQ%3D%3D',
            'context': _context(client),
          },
          client,
        );
        final tracks = _parseSearch(response, limit: limit);
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        // Пробуем следующий клиент.
      }
    }
    return const [];
  }

  /// Возвращает список прямых аудио-URL (сначала более высокое качество).
  Future<List<String>> audioUrls(String videoId) async {
    final target = _settings.bitrate;
    for (final client in _clients) {
      try {
        final response = await _post(
          'player',
          {
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
            'context': _context(client),
          },
          client,
        );
        final urls = _parseAudioUrls(response, target: target);
        if (urls.isNotEmpty) return urls;
      } catch (_) {
        // Пробуем следующий клиент.
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
    _ClientProfile client,
  ) async {
    final response = await _dio.postUri<dynamic>(
      Uri.parse('$_base/$endpoint?key=$_apiKey&prettyPrint=false'),
      data: body,
      options: Options(
        responseType: ResponseType.json,
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
    final data = response.data;
    return data is Map<String, dynamic> ? data : const {};
  }

  Map<String, dynamic> _context(_ClientProfile client) => {
        'client': {
          'clientName': client.name,
          'clientVersion': client.version,
          'hl': 'ru',
          'gl': 'RU',
          ...client.extra,
        },
      };

  List<Track> _parseSearch(Map<String, dynamic> data, {required int limit}) {
    final tracks = <Track>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (tracks.length >= limit) return;
      if (node is Map) {
        final renderer = node['videoRenderer'];
        if (renderer is Map<String, dynamic>) {
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

  Track? _videoToTrack(Map<String, dynamic> json) {
    final id = json['videoId'] as String?;
    if (id == null || id.isEmpty) return null;
    final title = _runsText(json['title']) ?? 'Без названия';
    final artist = _runsText(json['ownerText']) ??
        _runsText(json['longBylineText']) ??
        _runsText(json['shortBylineText']) ??
        'YouTube';
    final duration = _parseDuration(
      _simpleText(json['lengthText']) ??
          _simpleText(_access(json['lengthText'], ['simpleText'])),
    );
    final thumbs = _access(json['thumbnail'], ['thumbnails']);
    String? thumb;
    if (thumbs is List && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map) thumb = last['url'] as String?;
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

  List<String> _parseAudioUrls(
    Map<String, dynamic> data, {
    required int target,
  }) {
    final streaming = data['streamingData'];
    if (streaming is! Map) return const [];
    final formats = (streaming['adaptiveFormats'] as List?) ?? const [];
    final scored = <({int score, String url})>[];

    for (final raw in formats) {
      if (raw is! Map) continue;
      final mime = '${raw['mimeType'] ?? ''}'.toLowerCase();
      if (!mime.startsWith('audio/')) continue;
      final url = raw['url'] as String?;
      if (url == null || url.isEmpty) continue;
      final bitrate = (raw['bitrate'] as num?)?.toInt() ?? 128000;
      final kbps = bitrate > 10000 ? bitrate ~/ 1000 : bitrate;
      final isOpus = mime.contains('opus') || mime.contains('webm');
      var score = kbps - (kbps - target).abs() ~/ 2;
      if (isOpus) score += _settings.preferOpus ? 60 : -40;
      scored.add((score: score, url: url));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final out = <String>[];
    for (final item in scored) {
      if (!out.contains(item.url)) out.add(item.url);
      if (out.length >= 3) break;
    }
    return out;
  }

  String? _runsText(dynamic node) {
    if (node is Map) {
      final runs = node['runs'];
      if (runs is List && runs.isNotEmpty) {
        return runs
            .whereType<Map>()
            .map((r) => '${r['text'] ?? ''}')
            .join()
            .trim();
      }
      final simple = node['simpleText'];
      if (simple is String) return simple;
    }
    if (node is String) return node;
    return null;
  }

  String? _simpleText(dynamic node) {
    if (node is String) return node;
    if (node is Map && node['simpleText'] is String) {
      return node['simpleText'] as String;
    }
    return null;
  }

  dynamic _access(dynamic node, List<String> path) {
    dynamic current = node;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  Duration _parseDuration(String? raw) {
    if (raw == null || raw.isEmpty) return Duration.zero;
    final parts = raw.split(':').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    if (parts.isEmpty) return Duration.zero;
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part;
    }
    return Duration(seconds: seconds);
  }
}

class _ClientProfile {
  const _ClientProfile({
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
